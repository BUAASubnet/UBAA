import 'dart:async';

import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../../contracts/app_service.dart';
import '../state/state.dart';

mixin ControllerAppService on ControllerState {
  Future<AppServiceEraseOutcome>? _manualErase;
  Future<void>? _upload;
  bool _retryingErase = false;
  Future<void> _stateTail = Future.value();

  AppServiceView get appService => internalAppServiceView;
  PrivacyPolicyDocument get privacyPolicy => bundledPrivacyPolicy;

  AppServiceBackend? get _service => switch (internalBackend) {
    final AppServiceBackend service => service,
    _ => null,
  };

  bool _current(AppServiceBackend? service) =>
      !internalDisposed && identical(_service, service);

  void _show(AppServiceView view) {
    if (internalDisposed || appService == view) return;
    internalAppServiceView = view;
    internalNotify();
  }

  void _failure() => internalRecordFailure(
    StateError('应用服务操作未完成'),
    DiagnosticOperation.telemetry,
  );

  Future<AppServiceView> _queueState(
    Future<AppServiceView> Function(AppServiceBackend?) operation,
  ) {
    final service = _service;
    final next = _stateTail.then((_) async {
      if (!_current(service)) return appService;
      try {
        final state = await operation(service);
        if (_current(service)) {
          _show(
            (_manualErase != null && state.canErase) ||
                    (_retryingErase &&
                        state.erase == AppServiceEraseStatus.pending)
                ? state.withEraseStatus(AppServiceEraseStatus.running)
                : state,
          );
        }
      } on Object {
        if (_current(service)) _failure();
      }
      return appService;
    });
    _stateTail = next.then<void>((_) {});
    return next;
  }

  Future<AppServiceView> refreshAppService() => _queueState(
    (service) async =>
        await service?.appServiceState() ??
        AppServiceView.unavailable(privacyPolicy.version),
  );

  Future<AppServiceView> _change(
    Future<AppServiceView> Function(AppServiceBackend) action,
  ) => _queueState((service) async {
    if (service == null)
      return AppServiceView.unavailable(privacyPolicy.version);
    try {
      return await action(service);
    } on Object {
      if (_current(service)) _failure();
      return service.appServiceState();
    }
  });

  Future<AppServiceView> agreePrivacyPolicy() async {
    final previous = appService.consent;
    final state = await _change((service) => service.agreeAppService());
    if (previous != AppServiceConsent.agreed &&
        state.consent == AppServiceConsent.agreed) {
      // 首次同意之前没有入队，也不会为等待上传阻塞同意结果。
      unawaited(() async {
        await internalRecordAppOpen();
        await uploadAppService(force: true);
      }());
    }
    return state;
  }

  Future<AppServiceView> declinePrivacyPolicy() =>
      _change((service) => service.enterBasicAppService());

  Future<AppServiceView> withdrawPrivacyConsent() => declinePrivacyPolicy();

  Future<AppServiceView> setProductTelemetryEnabled(bool enabled) =>
      _change((service) => service.setAppServiceTelemetry(enabled));

  Future<AppServiceEraseOutcome> eraseUploadedTelemetry() {
    if (_manualErase case final pending?) return pending;
    final service = _service;
    if (service == null || internalDisposed) {
      return Future.value(AppServiceEraseOutcome.unavailable);
    }
    final completion = Completer<AppServiceEraseOutcome>();
    _manualErase = completion.future;
    unawaited(() async {
      var outcome = AppServiceEraseOutcome.unavailable;
      try {
        final state = await refreshAppService();
        if (!internalDisposed &&
            identical(_service, service) &&
            state.available &&
            state.canErase) {
          outcome = await service.eraseAppService();
        }
      } on Object {
        if (!internalDisposed && identical(_service, service)) _failure();
      } finally {
        _manualErase = null;
        if (!internalDisposed && identical(_service, service)) {
          final state = await refreshAppService();
          if (state.erase == AppServiceEraseStatus.pending) {
            outcome = AppServiceEraseOutcome.pending;
          }
        }
        completion.complete(outcome);
      }
    }());
    return completion.future;
  }

  /// 启动和移动端进入后台时使用 force；前台定时交由 Core 校验六小时。
  Future<void> uploadAppService({bool force = false}) {
    if (_upload case final pending?) return pending;
    if (_manualErase case final pending?) return pending.then<void>((_) {});
    final service = _service;
    if (service == null || internalDisposed) return Future.value();
    final completion = Completer<void>();
    _upload = completion.future;
    _retryingErase = appService.erase == AppServiceEraseStatus.pending;
    if (_retryingErase)
      _show(appService.withEraseStatus(AppServiceEraseStatus.running));
    unawaited(() async {
      try {
        await service.uploadAppService(force: force);
      } on Object {
        if (!internalDisposed && identical(_service, service)) _failure();
      } finally {
        _upload = null;
        _retryingErase = false;
        if (!internalDisposed && identical(_service, service)) {
          await refreshAppService();
        }
        completion.complete();
      }
    }());
    return completion.future;
  }

  Future<void> recordAppCrash(Object error, StackTrace? stackTrace) =>
      internalTrackTelemetry(
        TelemetryEvents.crash,
        properties: {
          'feature': 'app',
          'error_code': error.runtimeType.toString().split('<').first,
          'error_kind': 'internal',
          'retryable': false,
          if (telemetrySource(stackTrace) case final source?) 'source': source,
        },
      );

  void recordPresentedError(UiError error) => internalRecordVisibleError(error);

  Future<void> recordAppStarted() => internalRecordAppOpen();

  Future<void> setTelemetryEnabled(bool enabled) async {
    if (_service != null) {
      await setProductTelemetryEnabled(enabled);
    } else {
      internalSetLegacyTelemetryEnabled(enabled);
    }
  }

  Future<void> clearTelemetryQueue() => setTelemetryEnabled(false);
}
