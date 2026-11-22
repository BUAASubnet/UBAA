import 'dart:async';
import 'dart:convert';
import '../../backend/unavailable.dart';
import '../../contracts/app_service.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/lifecycle.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/activity.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;
import 'app_service.dart' show ControllerAppService;

mixin ControllerLifecycleActions on ControllerState, ControllerAppService {
  Future<CacheUsageSummary> cacheUsage({required String accountId}) =>
      internalReadCacheUsage(accountId);

  Future<CacheClearOutcome> clearBusinessCache({required String accountId}) =>
      internalClearControllerCache(accountId);

  SessionRecoveryStatus recoveryStatusFor(FeatureId feature) =>
      internalFeatureRecoveryStates[feature] ?? SessionRecoveryStatus.idle;

  /// 宿主在首页首帧之后调用；旧自动登录选项不参与是否开始检查的判断。
  void onHomeFirstFrame() {
    if (internalPhase == AppPhase.home) internalRecordFirstContent();
    if (internalHomeFrameReported ||
        !internalUsesLocalRecovery ||
        internalPhase != AppPhase.home)
      return;
    internalHomeFrameReported = true;
    if (internalSessionRecoveryStatus == SessionRecoveryStatus.idle) {
      unawaited(internalRecoverSession());
    }
  }

  Future<void> recoverSession({
    FeatureId feature = FeatureId.schedule,
    bool refreshHomeAfter = true,
  }) {
    if (internalNetworkFailure != null && internalNetworkOnline)
      internalCancelNetworkChange();
    final epoch = internalLifecycleEpoch;
    final before = internalFeatureRecoveryErrors[feature];
    final pending = internalRecoverSession(
      feature: feature,
      refreshHomeAfter: refreshHomeAfter,
    );
    if (_promptRecoveries[pending] != true) {
      _promptRecoveries[pending] = true;
      unawaited(
        pending.then(
          (_) {
            if (!internalDisposed && epoch == internalLifecycleEpoch) {
              final after = internalFeatureRecoveryErrors[feature];
              if (!identical(before, after))
                internalReportUserSchoolRejection(after);
            }
          },
          onError: (Object error) {
            if (!internalDisposed && epoch == internalLifecycleEpoch) {
              internalReportUserSchoolRejection(error);
            }
          },
        ),
      );
    }
    return pending;
  }

  final _promptRecoveries = Expando<bool>();

  /// 生命周期只更新可见状态；后台不开始未发送的恢复或首页同步。
  void setAppForeground(bool foreground) {
    final becameForeground = foreground && !internalAppForeground;
    internalAppForeground = foreground;
    if (!foreground) {
      internalCancelLoginVerification();
      internalLockDisplay?.cancel();
    }
    if (becameForeground &&
        internalPhase == AppPhase.login &&
        internalBackendNeedsRebuild) {
      unawaited(rebuildBackend());
    }
    if (foreground) internalDrainDeferredRecovery();
    internalSyncRecoveryRetries();
    internalPumpReadTasks();
  }

  /// 本地网络变化只是唤醒提示，成功与否仍由原会话检查判断。
  void onNetworkChanged({bool online = true}) =>
      internalHandleNetworkChange(online: online);

  /// 返回前台复用当前实例；旧宿主已认证首页也转入同一恢复协调路径。
  Future<void> resumeSession() {
    if (internalDisposed ||
        internalPhase != AppPhase.home ||
        internalIsSigningOut)
      return Future<void>.value();
    if (!internalUsesLocalRecovery) {
      internalUsesLocalRecovery = true;
      internalSessionRecoveryStatus = SessionRecoveryStatus.ready;
    }
    if (internalBackend is NetworkChangeBackend) {
      internalHandleNetworkChange(online: internalNetworkOnline);
      return internalNetworkReady?.future ?? Future<void>.value();
    }
    return internalAutomaticSchoolAction(internalRecoverSession);
  }

  /// 只导出本次运行允许字段，不读取凭据、业务输入或磁盘会话。
  String exportDiagnostics({String? issueId}) =>
      internalDiagnostics.exportText(issueId: issueId);

  /// 主动分享时才读取原始响应，不写入普通诊断存储或遥测。
  String exportFullDiagnostics({String? summary}) {
    final report =
        jsonDecode(summary ?? exportDiagnostics()) as Map<String, dynamic>;
    report['schema_version'] = 4;
    report['report_type'] = 'full_diagnostics';
    report['contains_sensitive_data'] = true;
    final backend = internalBackend;
    report['raw_http'] = backend is RawDiagnosticsBackend
        ? jsonDecode((backend as RawDiagnosticsBackend).exportRawDiagnostics())
        : {
            'enabled': false,
            'unavailable_reason': 'backend_unavailable',
            'records': [],
          };
    return const JsonEncoder.withIndent('  ').convert(report);
  }

  Future<void> initialize({
    MaterialTransactionRecovery? materialRecovery,
    Future<bool> Function()? requestPrivacyAgreement,
  }) async {
    unawaited(refreshAppService().then((_) => internalRecordAppOpen()));
    final startupLoginNotice =
        materialRecovery != null && !internalInitialized && !internalDisposed
        ? internalDiagnostics.recordMaterialRecovery(
            materialRecovery,
            stage: DiagnosticInitializationStage.platformCapabilities,
          )
        : null;
    if (startupLoginNotice != null) {
      internalInitialized = true;
      internalError = startupLoginNotice;
      internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
      internalSetPhase(AppPhase.login);
    } else {
      if (!internalPrivacyAccepted) {
        await _preparePrivateStartup(requestPrivacyAgreement);
        if (!internalPrivacyAccepted || internalDisposed) return;
      }
      await internalInitializeController();
    }
    internalRecordColdStart();
  }

  Future<void> _preparePrivateStartup(
    Future<bool> Function()? requestAgreement,
  ) async {
    Credential? saved;
    var canResume = false;
    try {
      final index = await internalLocalAccountStore?.read();
      if (internalCredentialVault.isAvailable) {
        saved = await internalCredentialVault.read();
      }
      if (index != null) {
        canResume = index.canRestore && index.account != null;
      } else {
        canResume =
            saved?.isUsable == true &&
            (saved!.autoLogin || internalLocalAccountStore != null);
        if (internalBackend case final SavedSessionBackend backend
            when !canResume) {
          canResume = await backend.hasSavedSession();
        }
      }
    } on Object catch (error, stackTrace) {
      if (internalDisposed) return;
      internalRecordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
        initializationStage: DiagnosticInitializationStage.localAccountRestore,
      );
    }
    if (internalDisposed) return;
    if (canResume && requestAgreement != null && await requestAgreement())
      return;
    if (internalDisposed) return;
    if (saved != null && saved.isUsable && internalLoginFormRevision == 0) {
      internalLoginForm = internalLoginForm.copyWith(
        username: saved.username,
        password: saved.password,
        rememberPassword: true,
        autoLogin: saved.autoLogin,
      );
    }
    internalInitialized = true;
    internalSetPhase(AppPhase.login);
  }

  /// 在 Dart isolate 或宿主生命周期重建后替换 opaque backend。
  ///
  /// 新后端创建后才释放旧后端。待手动登录时保留表单，不启动会话恢复。
  @override
  Future<bool> rebuildBackend() async {
    final factory = internalBackendFactory;
    final forManualLogin = internalBackendNeedsRebuild;
    if (!internalPrivacyAccepted ||
        factory == null ||
        internalDisposed ||
        (forManualLogin && !internalAppForeground) ||
        internalRebuildingBackend ||
        isLoggingIn ||
        internalSessionRecoveryFuture != null ||
        internalActivities.hasActive ||
        internalWriteCoordinator.hasPendingOperation)
      return false;
    // 初始化正在读取旧 backend 的认证/路线状态时，生命周期重建会与旧
    // handle 竞争并可能把结果写入新实例；等待初始化完成后再由下一次
    // resumed 事件触发重建。
    if (internalPhase == AppPhase.loggingIn ||
        internalPhase == AppPhase.checkingSession) {
      return false;
    }
    final previousLoginError = internalPhase == AppPhase.login
        ? internalError
        : null;
    final errorRevision = internalLoginFormRevision;
    final completion = Completer<void>();
    internalBackendRebuildCompletion = completion;
    internalCancelLoginVerification(notify: false);
    if (!forManualLogin) internalReleaseLoginSecret();
    internalSessionLifecycle.beginRebuild();
    final activity = internalBeginOperationTransition(
      ControllerActivityKind.backendRebuild,
    );
    if (!forManualLogin) internalSetPhase(AppPhase.checkingSession);
    try {
      final replacement = await factory();
      if (replacement is UnavailableBackend) {
        throw InitializationException(replacement.failure);
      }
      if (identical(replacement, internalBackend)) {
        internalError = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
        internalSetPhase(AppPhase.login);
        return false;
      }
      final previous = internalBackend;
      try {
        await internalDisposeBackendOnce(previous);
      } on Object catch (error, stackTrace) {
        // 新实例已经创建；旧实例清理失败不能让新实例继续持有旧状态。
        internalRecordFailure(
          error,
          DiagnosticOperation.disposal,
          stackTrace: stackTrace,
        );
      }
      if (internalDisposed) {
        try {
          await internalDisposeBackendOnce(replacement);
        } on Object {
          // controller 已销毁时尽力释放新实例，不能向 UI 抛出异常。
        }
        return false;
      }
      internalClearCurrentSessionGrant();
      internalSessionLifecycle.replaceBackend(replacement);
      if (internalPrivacyAccepted &&
          replacement is HostPrivacyAppServiceBackend) {
        (replacement as HostPrivacyAppServiceBackend).allowHostPrivacy();
      }
      internalBackendNeedsRebuild = false;
      unawaited(refreshAppService());
      internalReplaceWriteCoordinator(replacement);
      if (forManualLogin) return true;
      internalInitialized = false;
      internalUser = null;
      internalActiveRoutes = const <ConnectionMode>[];
      internalResetFeatureSnapshots();
      internalSessionLifecycle.endRebuild();
      await internalInitializeController(
        previousLoginError: internalLoginFormRevision == errorRevision
            ? previousLoginError
            : null,
      );
      return true;
    } on Object catch (error, stackTrace) {
      if (internalDisposed) return false;
      internalError = internalRecordFailure(
        error,
        forManualLogin
            ? DiagnosticOperation.login
            : DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      internalSetPhase(AppPhase.login);
      return false;
    } finally {
      internalEndOperationTransition(activity);
      internalBackendRebuildCompletion = null;
      completion.complete();
      internalSessionLifecycle.endRebuild();
      internalNotify();
    }
  }

  Future<void> logout({
    bool clearSavedCredential = false,
    Future<void> Function()? clearLocalData,
  }) => internalLogoutController(
    clearSavedCredential: clearSavedCredential,
    clearLocalData: clearLocalData,
  );

  void clearError() {
    internalClearError();
  }

  @internal
  void internalClearError() {
    if (internalError == null) return;
    internalError = null;
    internalNotify();
  }

  @internal
  bool internalRoutePolicyHasSession(
    RoutePolicy policy,
    List<ConnectionMode> activeRoutes,
  ) => switch (policy) {
    RoutePolicy.auto => activeRoutes.isNotEmpty,
    RoutePolicy.direct => activeRoutes.contains(ConnectionMode.direct),
    RoutePolicy.webvpn => activeRoutes.contains(ConnectionMode.webvpn),
  };

  @internal
  void internalApplyRouteSettings(BackendRouteSettings settings) {
    internalActiveRoutes = List<ConnectionMode>.unmodifiable(
      settings.activeRoutes,
    );
    internalLoginForm = internalLoginForm.copyWith(
      routePolicy: settings.defaultPolicy,
    );
  }

  @internal
  Future<void> internalRefreshRouteSettings() async {
    final scope = internalCaptureSessionScope();
    if (scope.backend case final RouteSettingsBackend routeBackend) {
      try {
        final settings = await routeBackend.routeSettings();
        if (!scope.isCurrent) return;
        internalApplyRouteSettings(settings);
      } on Object catch (error, stackTrace) {
        if (!scope.isCurrent) return;
        // 登录已经成功时，路线状态读取失败不能把账号重新置为失败；清空
        // 不确定的活动槽位，后续读取仍由 Core 返回实际错误。
        internalActiveRoutes = const <ConnectionMode>[];
        internalRecordFailure(
          error,
          DiagnosticOperation.routeChange,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @internal
  void internalSetPhase(AppPhase phase) {
    if (phase == AppPhase.login) {
      internalCacheLifecycle.invalidateReads();
      internalSessionLifecycle.invalidate();
      internalYgdkGeneration++;
      internalWriteCoordinator.invalidate();
    }
    internalPhase = phase;
    internalNotify();
  }

  @internal
  void internalNotify() => internalAutomaticSchoolAction(() {
    internalSyncHome();
    internalLockDisplay?.validate();
    for (final service in internalRequiredRecoveryServices.values) {
      service.validateScopes();
    }
    internalSyncRecoveryRetries();
    internalDrainDeferredRecovery();
    internalPumpReadTasks();
    if (!internalDisposed) notifyListeners();
  });

  @internal
  Future<void> internalDisposeBackendOnce(UbaaBackend backend) {
    final existing = internalBackendDisposals[backend];
    if (existing != null) return existing;
    final recovery = internalRequiredRecoveryServices.remove(backend);
    final lifecycle = backend is BackendLifecycle
        ? backend as BackendLifecycle
        : null;
    final agenda = backend is AgendaProvider
        ? (backend as AgendaProvider).agenda
        : null;

    final completer = Completer<void>();
    internalBackendDisposals[backend] = completer.future;
    try {
      Future.wait<void>([
        if (recovery != null) recovery.close().then<void>((_) {}),
        if (agenda != null) agenda.dispose(),
        if (lifecycle != null) lifecycle.dispose(),
      ]).then<void>(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stackTrace) {
          completer.completeError(error, stackTrace);
        },
      );
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  @override
  void dispose() {
    if (internalDisposed) return;
    internalClearCurrentSessionGrant();
    internalCancelNetworkChange();
    internalDisposeHome();
    internalDisposeAppService();
    internalDisposeUpdatePrompts();
    internalCancelLoginVerification(notify: false);
    // 密码释放属于销毁操作，不能等待已撤销的登录任务迟到收尾。
    internalReleaseLoginSecret();
    internalInPlaceLogin = false;
    internalInteractiveInPlace = false;
    internalLockDisplay?.cancel();
    internalSessionLifecycle.dispose();
    for (final service in internalRequiredRecoveryServices.values) {
      unawaited(service.close());
    }
    for (final scope in internalReadScopes.toList()) {
      scope.cancel();
    }
    internalPruneScheduleImports();
    internalWriteRefreshes.clear();
    internalReadScheduler.close();
    internalCancelDeferredRecovery();
    internalSessionLifecycle.invalidate();
    internalYgdkGeneration++;
    internalWriteCoordinator.removeListener(internalNotify);
    internalWriteCoordinator.dispose();
    internalYgdkReadbackState = const YgdkReadbackState.empty();
    internalSnapshots[FeatureId.ygdk] = const FeatureSnapshot(
      feature: FeatureId.ygdk,
    );
    unawaited(internalDisposeBackendOnce(internalBackend).catchError((_) {}));
    super.dispose();
  }
}
