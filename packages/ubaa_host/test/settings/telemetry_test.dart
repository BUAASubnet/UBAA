import 'dart:async';
import 'dart:ui';

import 'package:ubaa_ui/src/app/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_host/src/crash_handlers.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  testWidgets('未配置统计服务的生产接线保持关闭并说明不可用', (tester) async {
    await tester.pumpWidget(UbaaAppHost(backend: _Backend()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final profile = tester.widget<ProfileView>(find.byType(ProfileView));
    expect(profile.appService, isNull);
  });

  testWidgets('服务拒绝或挂起时仍可进入首页，前台定时重试待删除标记', (tester) async {
    final backend = _ServiceBackend();
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    expect(backend.uploads, [true]);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // 服务未响应时业务可以继续；同一宿主不并发启动第二次定时重试。
    await tester.pump(const Duration(minutes: 30));
    expect(backend.uploads, [true]);
    backend.firstUpload.completeError(StateError('合成服务拒绝'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(backend.status, AppServiceEraseStatus.pending);

    await tester.pump(const Duration(minutes: 30));
    await tester.pumpAndSettle();
    expect(backend.uploads, [true, false]);
    expect(backend.status, AppServiceEraseStatus.idle);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('启动配置启动和前台刷新，不等待统计且不在后台刷新', (tester) async {
    final backend = _ServiceBackend()..consent = AppServiceConsent.agreed;
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    expect(backend.uploads, [true]);
    expect(backend.bootstraps, [true]);
    await tester.pump(const Duration(minutes: 30));
    expect(backend.bootstraps, [true, false]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 30));
    expect(backend.bootstraps, [true, false]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(backend.bootstraps, [true, false, false]);
    expect(backend.uploads, [true]);

    backend.firstUpload.complete();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('前台首次跨过实际尝试时间六小时的检查就发送统计和启动配置', (tester) async {
    final now = tester.binding.clock.now;
    final started = now();
    final backend = _ThrottledServiceBackend(now);
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pump(_ThrottledServiceBackend.startupClaimDelay);
    await tester.pumpAndSettle();

    final first = started.add(_ThrottledServiceBackend.startupClaimDelay);
    expect(backend.deliveries, [first]);
    expect(backend.refreshes, [first]);

    for (var minute = 30; minute <= 360; minute += 30) {
      await tester.pump(
        started.add(Duration(minutes: minute)).difference(now()),
      );
    }
    expect(backend.deliveries, [first]);
    expect(backend.refreshes, [first]);

    await tester.pump(const Duration(minutes: 30));
    expect(backend.deliveries, [first, now()]);
    expect(backend.refreshes, [first, now()]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('启动状态暂时不可读时前台定时检查恢复待删除请求', (tester) async {
    final backend = _ServiceBackend()
      ..failStateReads = true
      ..firstUpload.complete();
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    expect(backend.stateReads, greaterThan(0));
    expect(backend.uploads, isEmpty);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    backend.failStateReads = false;
    await tester.pump(const Duration(minutes: 30));
    expect(backend.uploads, [false]);
    expect(backend.status, AppServiceEraseStatus.idle);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('默认启用后可直接进入设置并关闭统计', (tester) async {
    final backend = _ConsentBackend();
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settings-product-telemetry')),
    );
    expect(tile.value, isTrue);
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-product-telemetry')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-product-telemetry')));
    await tester.pumpAndSettle();
    expect(backend.telemetryEnabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('前台自动恢复被更新门控拒绝时不弹出既有错误提示', (tester) async {
    final backend = _ServiceBackend()
      ..consent = AppServiceConsent.agreed
      ..firstUpload.complete();
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    backend.rejectRecovery = true;
    for (var i = 1; i <= 2; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backend.rejectedRecoveries, i);
      expect(find.byType(SnackBar), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('旧版基础模式重启后保持关闭，可从开关确认后重新启用', (tester) async {
    final backend = _ConsentBackend()..consent = AppServiceConsent.basic;
    for (var startup = 0; startup < 2; startup++) {
      await tester.pumpWidget(UbaaAppHost(backend: backend));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('settings-product-telemetry')),
      );
      expect(tile.value, isFalse);
      expect(backend.consent, AppServiceConsent.basic);
      if (startup == 0) await tester.pumpWidget(const SizedBox.shrink());
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-product-telemetry')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-product-telemetry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('privacy-consent-agree')));
    await tester.pumpAndSettle();
    expect(backend.consent, AppServiceConsent.agreed);
    expect(backend.telemetryEnabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('旧构建遇到尚未应用的政策状态仍可进入设置并保留关闭选择', (tester) async {
    for (final consent in [
      AppServiceConsent.unasked,
      AppServiceConsent.reconsentRequired,
    ]) {
      final backend = _ConsentBackend()
        ..consent = consent
        ..telemetryEnabled = false;
      await tester.pumpWidget(UbaaAppHost(backend: backend));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('settings-product-telemetry')),
      );
      expect(tile.value, isFalse);
      expect((backend.consent, backend.telemetryEnabled), (consent, false));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('框架与 root isolate 仍执行原处理，统计异常不重复进入错误链', () async {
    final dispatcher = PlatformDispatcher.instance;
    final originalFlutter = FlutterError.onError;
    final originalPlatform = dispatcher.onError;
    var flutterCalls = 0, platformCalls = 0;
    final seen = <Type>[];
    void priorFlutter(FlutterErrorDetails details) => flutterCalls++;
    bool priorPlatform(Object error, StackTrace stack) {
      platformCalls++;
      return true;
    }

    FlutterError.onError = priorFlutter;
    dispatcher.onError = priorPlatform;
    final handlers = DartCrashHandlers.install((error, _) async {
      seen.add(error.runtimeType);
      throw StateError('合成统计失败');
    });
    try {
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('框架异常')));
      expect(
        dispatcher.onError!(ArgumentError('异步异常'), StackTrace.current),
        isTrue,
      );
      expect((flutterCalls, platformCalls), (1, 1));
      await Future<void>.delayed(Duration.zero);
      expect(seen, [StateError, ArgumentError]);
      expect((flutterCalls, platformCalls), (1, 1));
      handlers.dispose();
      expect(FlutterError.onError, priorFlutter);
      expect(dispatcher.onError, priorPlatform);
    } finally {
      FlutterError.onError = originalFlutter;
      dispatcher.onError = originalPlatform;
    }
  });
}

class _Backend extends DemoBackend {
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
}

class _ServiceBackend extends _Backend implements AppBootstrapBackend {
  final uploads = <bool>[];
  final bootstraps = <bool>[];
  final firstUpload = Completer<void>();
  var status = AppServiceEraseStatus.pending;
  var consent = AppServiceConsent.basic;
  bool failStateReads = false;
  int stateReads = 0;
  bool rejectRecovery = false;
  int rejectedRecoveries = 0;

  @override
  Future<AuthStatus> authStatus() async {
    if (rejectRecovery) {
      rejectedRecoveries++;
      throw const BackendException(UbaaErrorCode.updateRequired);
    }
    return super.authStatus();
  }

  @override
  Future<AppServiceView> appServiceState() async {
    stateReads++;
    if (failStateReads) throw StateError('合成存储暂不可读');
    return AppServiceView(
      available: true,
      telemetryAllowed: true,
      consent: consent,
      policyVersion: bundledPrivacyPolicy.version,
      agreedPolicyVersion: null,
      telemetryEnabled: false,
      canErase: true,
      erase: status,
    );
  }

  @override
  Future<void> uploadAppService({required bool force}) async {
    uploads.add(force);
    if (uploads.length == 1) await firstUpload.future;
    status = AppServiceEraseStatus.idle;
  }

  @override
  Future<void> refreshAppBootstrap({required bool force}) async {
    if (consent == AppServiceConsent.agreed) bootstraps.add(force);
  }

  @override
  Future<AppServiceView> markAppAnnouncementRead(String id) =>
      appServiceState();
  @override
  Future<AppServiceView> dismissAppUpdateAvailable(String latestVersion) =>
      appServiceState();

  @override
  Future<AppServiceView> agreeAppService() => throw UnimplementedError();
  @override
  Future<AppServiceView> enterBasicAppService() => throw UnimplementedError();
  @override
  Future<AppServiceView> setAppServiceTelemetry(bool enabled) =>
      throw UnimplementedError();
  @override
  Future<AppServiceEraseOutcome> eraseAppService() =>
      throw UnimplementedError();
  @override
  Future<void> recordAppService(TelemetryRecord record) =>
      throw UnimplementedError();
}

/// 模拟 Core 按实际写入的尝试时间节流，启动时写入比前台计时器晚一点。
class _ThrottledServiceBackend extends _ServiceBackend {
  _ThrottledServiceBackend(this.now) {
    consent = AppServiceConsent.agreed;
    status = AppServiceEraseStatus.idle;
  }

  static const startupClaimDelay = Duration(milliseconds: 25);
  final DateTime Function() now;
  final deliveries = <DateTime>[];
  final refreshes = <DateTime>[];

  Future<void> _claim(List<DateTime> attempts, bool force) async {
    if (force) await Future<void>.delayed(startupClaimDelay);
    final time = now();
    if (force || time.difference(attempts.last) >= const Duration(hours: 6)) {
      attempts.add(time);
    }
  }

  @override
  Future<void> uploadAppService({required bool force}) =>
      _claim(deliveries, force);

  @override
  Future<void> refreshAppBootstrap({required bool force}) =>
      _claim(refreshes, force);
}

/// 投影 Core 打开图形服务后保存的默认状态与用户选择。
class _ConsentBackend extends _Backend implements AppServiceBackend {
  var consent = AppServiceConsent.agreed;
  var telemetryEnabled = true;
  var everAgreed = true;

  AppServiceView get _view => AppServiceView(
    available: true,
    telemetryAllowed: true,
    consent: consent,
    policyVersion: bundledPrivacyPolicy.version,
    agreedPolicyVersion: consent == AppServiceConsent.agreed
        ? bundledPrivacyPolicy.version
        : null,
    telemetryEnabled: telemetryEnabled,
    canErase: everAgreed,
    erase: AppServiceEraseStatus.idle,
  );

  @override
  Future<AppServiceView> appServiceState() async => _view;
  @override
  Future<AppServiceView> agreeAppService() async {
    if (!everAgreed) telemetryEnabled = true;
    everAgreed = true;
    consent = AppServiceConsent.agreed;
    return _view;
  }

  @override
  Future<AppServiceView> enterBasicAppService() async {
    consent = AppServiceConsent.basic;
    return _view;
  }

  @override
  Future<AppServiceView> setAppServiceTelemetry(bool enabled) async {
    telemetryEnabled = enabled;
    return _view;
  }

  @override
  Future<AppServiceEraseOutcome> eraseAppService() async =>
      AppServiceEraseOutcome.succeeded;
  @override
  Future<void> uploadAppService({required bool force}) async {}
  @override
  Future<void> recordAppService(TelemetryRecord record) async {}
}
