import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('登录后独立加载普通与高级只读功能', () async {
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      credentialVault: MemoryCredentialVault(),
    );
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    controller.setUsername('2020000000');
    controller.setPassword('not-a-real-password');
    await controller.submitLogin();
    expect(controller.phase, AppPhase.home);
    await controller.refreshHome();
    expect(
      controller.snapshots.values.every(
        (snapshot) => snapshot.status == FeatureLoadStatus.success,
      ),
      isTrue,
    );
    controller.dispose();
  });

  test('生产能力不可用时不伪造 Demo 登录成功', () async {
    final controller = AppController(backend: const UnavailableBackend());
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    expect(controller.error?.code, UbaaErrorCode.unsupported);
    controller.dispose();
  });

  test('安全保险箱明确开启自动登录时恢复会话并清理密码', () async {
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: '2020000000',
          password: 'saved-secret',
          autoLogin: true,
        ),
      ),
    );
    await controller.initialize();
    expect(controller.phase, AppPhase.home);
    expect(controller.user?.username, '2020000000');
    expect(controller.loginForm.password, isEmpty);
    expect(controller.loginForm.autoLogin, isTrue);
    controller.dispose();
  });

  test('错误映射不暴露上游细节', () {
    final error = UbaaErrorMapper.fromCode(UbaaErrorCode.networkError);
    expect(error.message, contains('校园网'));
    expect(error.message, isNot(contains('http')));
    expect(error.retryable, isTrue);
  });

  test('刷新失败时保留上次数据并标记 stale', () async {
    var loads = 0;
    final backend = _FlakyBackend(
      load: (_) async {
        loads++;
        if (loads > 1) {
          throw const BackendException(UbaaErrorCode.networkError);
        }
        return const FeatureResult.success(
          summary: '上次成功数据',
          details: <FeatureDetail>[
            FeatureDetail(title: '课程', subtitle: '保留内容'),
          ],
        );
      },
    );
    final controller = AppController(backend: backend);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    expect(
      controller.snapshots[FeatureId.schedule]!.status,
      FeatureLoadStatus.success,
    );
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.stale);
    expect(snapshot.details.single.title, '课程');
    expect(snapshot.error?.code, UbaaErrorCode.networkError);
    controller.dispose();
  });

  test('Core 明确返回空结果时清除上次成功摘要和详情', () async {
    var loads = 0;
    final backend = _FlakyBackend(
      load: (_) async {
        loads++;
        return loads == 1
            ? const FeatureResult.success(
                summary: '上次成功数据',
                details: <FeatureDetail>[FeatureDetail(title: '课程')],
              )
            : const FeatureResult.empty();
      },
    );
    final controller = AppController(backend: backend);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    await controller.refreshHome(only: const <FeatureId>[FeatureId.schedule]);
    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.empty);
    expect(snapshot.summary, isNull);
    expect(snapshot.details, isEmpty);
    controller.dispose();
  });

  test('领域查询参数通过 FeatureQueryBackend typed 传递', () async {
    FeatureQuery? received;
    final backend = _QueryBackend(
      onQuery: (_, query) {
        received = query;
        return const FeatureResult.success(
          summary: '指定查询',
          details: <FeatureDetail>[FeatureDetail(title: '查询结果')],
        );
      },
    );
    final controller = AppController(backend: backend);
    await controller.refreshFeatureQuery(
      FeatureId.classroom,
      FeatureQuery(
        date: DateTime(2026, 9, 2),
        campus: 2,
        week: 3,
        page: 1,
        size: 10,
      ),
    );
    expect(received?.campus, 2);
    expect(received?.week, 3);
    expect(received?.page, 1);
    expect(controller.snapshots[FeatureId.classroom]!.summary, '指定查询');
    controller.dispose();
  });
}

class _FlakyBackend implements UbaaBackend {
  _FlakyBackend({required this.load});

  final Future<FeatureResult> Function(FeatureId) load;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) => load(feature);
}

class _QueryBackend implements UbaaBackend, FeatureQueryBackend {
  _QueryBackend({required this.onQuery});

  final FeatureResult Function(FeatureId, FeatureQuery) onQuery;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => onQuery(feature, query);
}
