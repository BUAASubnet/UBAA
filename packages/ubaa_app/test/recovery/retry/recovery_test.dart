import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;

Future<AppController> start(fixtures.FakeRecoveryBackend backend) async {
  final controller = AppController(
    backend: backend,
    localAccountStore: await fixtures.savedAccounts(),
  );
  await controller.initialize();
  controller.onHomeFirstFrame();
  await controller.recoverSession();
  return controller;
}

void main() {
  testWidgets('临时恢复失败前台按30秒60秒5分钟退避，成功后停止', (tester) async {
    final backend = fixtures.FakeRecoveryBackend()
      ..authError = const BackendException(UbaaErrorCode.networkError);
    final controller = await start(backend);
    addTearDown(controller.dispose);
    expect(backend.authCalls, 1);
    await tester.pump(const Duration(seconds: 29));
    expect(backend.authCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(backend.authCalls, 2);
    await tester.pump(const Duration(seconds: 59));
    expect(backend.authCalls, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(backend.authCalls, 3);
    await tester.pump(const Duration(seconds: 299));
    expect(backend.authCalls, 3);
    backend.authError = null;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(backend.authCalls, 4);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(backend.readCalls, greaterThan(0));
    await tester.pump(const Duration(minutes: 10));
    expect(backend.authCalls, 4);
    expect(backend.loginCalls, 0);
    controller.dispose();
  });
  testWidgets('后台不轮询，网络变化与显式恢复合并在途任务，退出撤销计时器', (tester) async {
    final backend = fixtures.FakeRecoveryBackend()
      ..authError = const BackendException(UbaaErrorCode.timeout);
    final controller = await start(backend);
    addTearDown(controller.dispose);
    controller.setAppForeground(false);
    await tester.pump(const Duration(minutes: 10));
    controller.onNetworkChanged();
    await tester.pump();
    expect(backend.authCalls, 1);
    backend.authError = null;
    backend.gate = Completer<AuthStatus>();
    controller.setAppForeground(true);
    controller.onNetworkChanged();
    controller.onNetworkChanged();
    final pending = controller.recoverSession();
    await tester.pump();
    expect(backend.authCalls, 2);
    backend.gate!.complete(AuthStatus.signedIn);
    await pending;
    await tester.pumpAndSettle();
    expect(backend.authCalls, 2);
    await controller.logout();
    controller.onNetworkChanged();
    await tester.pump(const Duration(minutes: 10));
    expect(backend.authCalls, 2);
    controller.dispose();
  });
  testWidgets('退避与网络提示不能越过待确认写意图，取消后只恢复不提交', (tester) async {
    final backend = _WriteBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    backend.authError = const BackendException(UbaaErrorCode.networkError);
    await controller.recoverSession(
      feature: FeatureId.grades,
      refreshHomeAfter: false,
    );
    backend.authError = null;
    await controller.recoverSession();
    controller.writeCoordinator.setIntent(
      WriteIntent(
        intentId: 'synthetic',
        operation: WriteOperation.bykcSelectCourse,
        targetSummary: '合成目标',
        resolvedRoute: ConnectionMode.direct,
        warnings: const [],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        requestDigest: 'synthetic',
      ),
    );
    controller.onNetworkChanged();
    await tester.pump(const Duration(minutes: 10));
    expect(backend.authCalls, 3);
    expect(controller.writeCoordinator.intent, isNotNull);
    backend.authError = null;
    await controller.writeCoordinator.cancelForUi();
    await tester.pumpAndSettle();
    expect(backend.authCalls, 4);
    expect(backend.commits, 0);
    controller.dispose();
  });
  testWidgets('网络变化恢复后原位重读失败查询，保持学期且重复提示不新增任务', (tester) async {
    final backend = _QueryBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    const query = FeatureQuery(term: 'synthetic-term');
    await controller.refreshFeatureQuery(FeatureId.grades, query);
    expect(
      controller.snapshots[FeatureId.grades]!.error?.code,
      UbaaErrorCode.networkError,
    );
    expect(backend.queries, 1);
    backend.fail = false;
    controller.onNetworkChanged();
    controller.onNetworkChanged();
    await tester.pumpAndSettle();
    expect(backend.queries, 2);
    expect(
      controller.snapshots[FeatureId.grades]!.readContext?.hasSameQuery(query),
      isTrue,
    );
    expect(controller.snapshots[FeatureId.grades]!.error, isNull);
    expect(
      controller.snapshots[FeatureId.grades]!.details.single.title,
      '合成成绩',
    );
    controller.dispose();
  });
  for (final code in [
    UbaaErrorCode.invalidCredentials,
    UbaaErrorCode.authenticationRequired,
    UbaaErrorCode.upstreamChanged,
    UbaaErrorCode.internalError,
    UbaaErrorCode.unsupported,
  ]) {
    testWidgets('${code.name}不自动重试认证或密码', (tester) async {
      final backend = fixtures.FakeRecoveryBackend()
        ..authError = BackendException(code);
      final controller = await start(backend);
      addTearDown(controller.dispose);
      controller.onNetworkChanged();
      await tester.pump(const Duration(minutes: 10));
      expect(backend.authCalls, 1);
      expect(backend.loginCalls, 0);
      controller.dispose();
    });
  }
  testWidgets('明确不可重试的临时错误和销毁后的回调不启动恢复', (tester) async {
    final backend = fixtures.FakeRecoveryBackend()
      ..authError = const BackendException(
        UbaaErrorCode.upstreamUnavailable,
        retryable: false,
      );
    final controller = await start(backend);
    controller.onNetworkChanged();
    await tester.pump(const Duration(minutes: 10));
    expect(backend.authCalls, 1);
    controller.dispose();
    controller.onNetworkChanged();
    await tester.pump(const Duration(minutes: 10));
    expect(backend.authCalls, 1);
  });
}

class _WriteBackend extends fixtures.FakeRecoveryBackend
    implements WriteCommitBackend {
  int commits = 0;
  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commits++;
    throw StateError('恢复测试禁止写入');
  }
}

class _QueryBackend extends fixtures.FakeRecoveryBackend
    implements FeatureQueryBackend {
  bool fail = true;
  int queries = 0;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries++;
    if (fail) throw const BackendException(UbaaErrorCode.networkError);
    return const FeatureResult.success(
      summary: '合成成绩',
      details: [FeatureDetail(title: '合成成绩')],
    );
  }
}
