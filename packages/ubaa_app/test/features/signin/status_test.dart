import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;

import '../../support/controller/fakes.dart';

const _signin = SigninPerformAction(
  scheduleId: '课次',
  eligibility: ActionEligibility.allowed,
);

void main() {
  test('每次在线检查读取新状态并更新上课快照', () async {
    final (controller, backend) = await _start();
    expect(await controller.checkSigninSigned('课次'), isFalse);
    backend.next = () async => _result(1);
    expect(await controller.checkSigninSigned('课次'), isTrue);
    expect(_status(controller), 1);
    expect(backend.onlineReads, 2);
  });

  test('找不到排课或在线请求失败时抛错', () async {
    final (controller, backend) = await _start();
    expect(await controller.checkSigninSigned('课次'), isFalse);
    await expectLater(
      controller.checkSigninSigned('不存在'),
      throwsA(isA<BackendException>()),
    );
    backend.next = () async =>
        throw const BackendException(UbaaErrorCode.networkError);
    await expectLater(
      controller.checkSigninSigned('课次'),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '错误码',
          UbaaErrorCode.networkError,
        ),
      ),
    );
  });

  test('多个排课同时检查时合用一次今日列表读取', () async {
    final (controller, backend) = await _start();
    final pending = Completer<FeatureResult>();
    backend.next = () => pending.future;
    final first = controller.checkSigninSigned('课次');
    final second = controller.checkSigninSigned('另一排课');
    pending.complete(_result(1));
    await Future.wait<void>([
      expectLater(first, completion(isTrue)),
      expectLater(second, throwsA(isA<BackendException>())),
    ]);
    expect(backend.onlineReads, 1);
  });

  test('上课提交成功仍通过原路线回读更新卡片数据', () async {
    final (controller, backend) = await _start();
    final coordinator = controller.writeCoordinator;
    final intent = await _prepareSignin(controller);
    expect(intent, isNotNull);
    await coordinator.confirmForUi();
    expect(backend.commitCalls, 1);
    expect(backend.pinnedRoutes, [ConnectionMode.direct]);
    expect(_status(controller), 1);
  });

  test('WebVPN 上课预检需要认证时，自动登录后复核并仅提交一次', () async {
    final (controller, backend) = await _startRecovery();
    final intent = await _prepareSignin(controller);

    expect(intent?.resolvedRoute, ConnectionMode.webvpn);
    expect(backend.recoveryTargets, [FeatureId.signin]);
    expect(backend.loginRoutes, [ConnectionMode.webvpn]);
    expect(backend.prepareCalls, 2);
    expect(backend.commitCalls, 0);

    expect(
      (await controller.writeCoordinator.confirmForUi())?.result?.success,
      isTrue,
    );
    expect(backend.commitCalls, 1);
    expect(backend.pinnedRoutes, [ConnectionMode.webvpn]);
  });

  test('未开启自动登录时，上课预检不会使用已保存的密码', () async {
    final (controller, backend) = await _startRecovery(autoLogin: false);

    await expectLater(
      _prepareSignin(controller),
      throwsA(_uiError(UbaaErrorCode.authenticationRequired)),
    );
    expect(backend.recoveryTargets, [FeatureId.signin]);
    expect(backend.loginRoutes, isEmpty);
    expect(backend.prepareCalls, 1);
    expect(backend.commitCalls, 0);
  });

  for (final code in [
    UbaaErrorCode.invalidInput,
    UbaaErrorCode.authenticationRequired,
  ]) {
    test('恢复后的上课预检失败时结束本次操作（${code.name}）', () async {
      final (controller, backend) = await _startRecovery();
      backend.afterLoginError = BackendException(
        code,
        resolvedRoute: ConnectionMode.webvpn,
      );

      await expectLater(_prepareSignin(controller), throwsA(_uiError(code)));
      expect(backend.recoveryTargets, [FeatureId.signin]);
      expect(backend.loginRoutes, [ConnectionMode.webvpn]);
      expect(backend.prepareCalls, 2);
      expect(controller.writeCoordinator.intent, isNull);
      expect(backend.commitCalls, 0);
    });
  }
}

Matcher _uiError(UbaaErrorCode code) =>
    isA<UiError>().having((error) => error.code, '错误码', code);

Future<WriteIntent?> _prepareSignin(AppController controller) =>
    controller.writeCoordinator.prepareForUi(
      () => controller.prepareSigninWrite(_signin),
      expectedOperation: _signin.operation,
    );

Future<(AppController, _RecoveryBackend)> _startRecovery({
  bool autoLogin = true,
}) async {
  final backend = _RecoveryBackend();
  final controller = AppController(
    backend: backend,
    localAccountStore: await support.savedAccounts(),
    credentialVault: MemoryCredentialVault(
      initial: Credential(
        username: 'fixture-user',
        password: 'synthetic',
        autoLogin: autoLogin,
      ),
    ),
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  await controller.recoverSession(refreshHomeAfter: false);
  backend.recoveryTargets.clear();
  return (controller, backend);
}

int? _status(AppController controller) =>
    (controller.snapshots[FeatureId.signin]!.details.single.presentation
            as SigninPresentation)
        .signStatus;

Future<(AppController, _Backend)> _start() async {
  final backend = _Backend();
  final controller = AppController(backend: backend);
  addTearDown(controller.dispose);
  await controller.initialize();
  await controller.refreshHome(only: [FeatureId.signin]);
  await Future<void>.delayed(Duration.zero);
  return (controller, backend);
}

FeatureResult _result(int status) => FeatureResult.success(
  resolvedRoute: ConnectionMode.direct,
  details: [
    FeatureDetail(
      title: '课程',
      presentation: SigninPresentation(
        courseId: '展示课程',
        actionTarget: '课次',
        classBeginTime: '08:00',
        classEndTime: '09:40',
        signStatus: status,
      ),
    ),
  ],
);

final class _Backend extends FixtureSigninWriteBackend
    implements SigninReadbackBackend, PinnedWriteReadbackBackend {
  int onlineReads = 0;
  final pinnedRoutes = <ConnectionMode>[];
  Future<FeatureResult> Function() next = () async => _result(0);

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature == FeatureId.signin
      ? _result(commitCalls == 0 ? 0 : 1)
      : const FeatureResult.empty();

  @override
  Future<FeatureResult> readSigninAfterWrite() {
    onlineReads++;
    return next();
  }

  @override
  Future<FeatureResult> readAfterWriteOnRoute(
    WriteOperation operation, {
    required ConnectionMode route,
    FeatureQuery? query,
  }) async {
    pinnedRoutes.add(route);
    return _result(1);
  }
}

final class _RecoveryBackend extends _Backend
    implements RequiredSessionBackend {
  final recoveryTargets = <FeatureId>[];
  final loginRoutes = <ConnectionMode>[];
  int prepareCalls = 0;
  bool webvpnReady = false;
  BackendException? afterLoginError;

  static const _expired = BackendException(
    UbaaErrorCode.authenticationRequired,
    resolvedRoute: ConnectionMode.webvpn,
  );

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-user');

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    recoveryTargets.add(feature);
    final signin = feature == FeatureId.signin;
    if (signin && !webvpnReady) throw _expired;
    return RecoveredRouteSession(
      route: signin ? ConnectionMode.webvpn : ConnectionMode.direct,
      profile: (await userInfo())!,
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    loginRoutes.add(route);
    webvpnReady = true;
    return RecoveredRouteSession(route: route, profile: (await userInfo())!);
  }

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    prepareCalls++;
    if (!webvpnReady) throw _expired;
    if (afterLoginError case final error?) throw error;
    return WriteIntent(
      intentId: 'signin-intent',
      operation: WriteOperation.signinPerform,
      targetSummary: courseId,
      resolvedRoute: ConnectionMode.webvpn,
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      warnings: const [],
      requestDigest: 'fixture',
    );
  }
}
