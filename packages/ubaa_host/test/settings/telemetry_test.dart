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
    expect(profile.telemetryAvailable, isFalse);
    expect(profile.telemetryEnabled, isFalse);
    expect(find.widgetWithText(SwitchListTile, '匿名产品改进统计'), findsNothing);
  });

  testWidgets('服务拒绝或挂起时仍可进入首页，前台定时重试待删除标记', (tester) async {
    final backend = _ServiceBackend();
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    expect(backend.uploads, [true]);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // 服务未响应时业务可以继续；同一宿主不并发启动第二次定时重试。
    await tester.pump(const Duration(hours: 6));
    expect(backend.uploads, [true]);
    backend.firstUpload.completeError(StateError('合成服务拒绝'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(backend.status, AppServiceEraseStatus.pending);

    await tester.pump(const Duration(hours: 6));
    await tester.pumpAndSettle();
    expect(backend.uploads, [true, false]);
    expect(backend.status, AppServiceEraseStatus.idle);
    await tester.pumpWidget(const SizedBox.shrink());
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

class _ServiceBackend extends _Backend implements AppServiceBackend {
  final uploads = <bool>[];
  final firstUpload = Completer<void>();
  var status = AppServiceEraseStatus.pending;

  @override
  Future<AppServiceView> appServiceState() async => AppServiceView(
    available: true,
    telemetryAllowed: true,
    consent: AppServiceConsent.basic,
    policyVersion: bundledPrivacyPolicy.version,
    agreedPolicyVersion: null,
    telemetryEnabled: false,
    canErase: true,
    erase: status,
  );

  @override
  Future<void> uploadAppService({required bool force}) async {
    uploads.add(force);
    if (uploads.length == 1) return firstUpload.future;
    status = AppServiceEraseStatus.idle;
  }

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
