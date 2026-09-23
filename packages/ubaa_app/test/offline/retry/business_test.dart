import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../startup_test.dart' as fixtures;
import 'recovery_test.dart' show start;

void main() {
  testWidgets('认证健康时业务临时失败仍按30秒60秒5分钟退避且成功停止', (tester) async {
    final backend = BusinessBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    const query = FeatureQuery(term: 'synthetic-term');
    await controller.refreshFeatureQuery(FeatureId.grades, query);
    expect(backend.queries.length, 1);
    await tester.pump(const Duration(seconds: 29));
    expect(backend.queries.length, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(backend.queries.length, 2);
    await tester.pump(const Duration(seconds: 59));
    expect(backend.queries.length, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(backend.queries.length, 3);
    backend.fail = false;
    await tester.pump(const Duration(seconds: 299));
    expect(backend.queries.length, 3);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(backend.queries.length, 4);
    expect(controller.snapshots[FeatureId.grades]!.error, isNull);
    await tester.pump(const Duration(minutes: 10));
    expect(backend.queries.length, 4);
    expect(backend.authCalls, 1);
    expect(backend.loginCalls, 0);
    controller.dispose();
  });
  testWidgets('业务退避在后台和待确认写入时停止，恢复后不提交且新查询撤销旧任务', (tester) async {
    final backend = BusinessBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    const old = FeatureQuery(term: 'old-term');
    const fresh = FeatureQuery(term: 'new-term');
    await controller.refreshFeatureQuery(FeatureId.grades, old);
    controller.setAppForeground(false);
    await tester.pump(const Duration(minutes: 10));
    expect(backend.queries.length, 1);
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
    controller.setAppForeground(true);
    await tester.pump(const Duration(minutes: 10));
    expect(backend.queries.length, 1);
    await controller.writeCoordinator.cancelForUi();
    backend.fail = false;
    await controller.refreshFeatureQuery(FeatureId.grades, fresh);
    await tester.pump(const Duration(minutes: 10));
    expect(backend.queries.map((query) => query.term), [
      'old-term',
      'new-term',
    ]);
    expect(backend.commits, 0);
    controller.dispose();
  });
  testWidgets('网络唤醒与定时重试合并在途查询，退出拒绝迟到结果和后续计时', (tester) async {
    final backend = BusinessBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    await controller.refreshFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(term: 'synthetic'),
    );
    backend.readGate = Completer<FeatureResult>();
    controller.onNetworkChanged();
    controller.onNetworkChanged();
    await tester.pump();
    expect(backend.queries.length, 2);
    await tester.pump(const Duration(minutes: 10));
    controller.onNetworkChanged();
    await tester.pump();
    expect(backend.queries.length, 2);
    expect(backend.authCalls, 1);
    await controller.logout();
    backend.readGate!.complete(const FeatureResult.success(summary: '迟到合成内容'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 10));
    expect(backend.queries.length, 2);
    expect(controller.phase, AppPhase.login);
    expect(controller.snapshots[FeatureId.grades]!.summary, isNot('迟到合成内容'));
    expect(backend.commits, 0);
    controller.dispose();
  });
  for (final code in [
    UbaaErrorCode.upstreamChanged,
    UbaaErrorCode.authenticationRequired,
    UbaaErrorCode.internalError,
  ]) {
    testWidgets('${code.name}业务失败不自动重试', (tester) async {
      final backend = BusinessBackend()..failureCode = code;
      final controller = await start(backend);
      addTearDown(controller.dispose);
      await controller.refreshFeatureQuery(
        FeatureId.grades,
        const FeatureQuery(),
      );
      await tester.pump(const Duration(minutes: 10));
      expect(backend.queries.length, 1);
      expect(backend.loginCalls, 0);
      controller.dispose();
    });
  }
  testWidgets('首页默认失败重试不覆盖已打开的精确查询', (tester) async {
    final backend = BusinessBackend()..homeFail = true;
    final controller = await start(backend);
    addTearDown(controller.dispose);
    backend.fail = false;
    await controller.refreshFeatureQuery(
      FeatureId.spoc,
      const FeatureQuery(term: 'explicit'),
    );
    final before = backend.homeReads;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(backend.homeReads, before + 1);
    expect(
      controller.snapshots[FeatureId.spoc]!.readContext?.query?.term,
      'explicit',
    );
    expect(controller.snapshots[FeatureId.spoc]!.summary, '合成结果');
    controller.dispose();
  });
  testWidgets('另一个领域恢复失败不阻止已就绪领域的业务退避', (tester) async {
    final backend = RouteBusinessBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    await tester.pumpAndSettle();
    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(term: 'synthetic'),
    );
    backend.authError = const BackendException(UbaaErrorCode.networkError);
    await controller.recoverSession(
      feature: FeatureId.grades,
      refreshHomeAfter: false,
    );
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.unavailable);
    backend.fail = false;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(backend.queries.length, 2);
    expect(controller.snapshots[FeatureId.schedule]!.error, isNull);
    controller.dispose();
  });
  testWidgets('已打开显式页时首页新失败也能登记并启动退避', (tester) async {
    final backend = BusinessBackend()..fail = false;
    final controller = await start(backend);
    addTearDown(controller.dispose);
    await controller.refreshFeatureQuery(
      FeatureId.spoc,
      const FeatureQuery(term: 'explicit'),
    );
    backend.homeFail = true;
    await controller.refreshHome(only: [FeatureId.spoc]);
    final before = backend.homeReads;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(backend.homeReads, before + 1);
    expect(
      controller.snapshots[FeatureId.spoc]!.readContext?.query?.term,
      'explicit',
    );
    controller.dispose();
  });
}

class BusinessBackend extends fixtures.FakeRecoveryBackend
    implements FeatureQueryBackend, WriteCommitBackend {
  bool fail = true;
  bool homeFail = false;
  int homeReads = 0;
  UbaaErrorCode failureCode = UbaaErrorCode.networkError;
  int commits = 0;
  final queries = <FeatureQuery>[];
  Completer<FeatureResult>? readGate;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add(query);
    if (readGate case final gate?) return gate.future;
    if (fail)
      return FeatureResult.failure(UbaaErrorMapper.fromCode(failureCode));
    return const FeatureResult.success(summary: '合成结果');
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (feature == FeatureId.spoc) {
      homeReads++;
      if (homeFail)
        return FeatureResult.failure(UbaaErrorMapper.fromCode(failureCode));
    }
    return super.loadFeature(feature);
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commits++;
    throw StateError('合成重试测试不提交');
  }
}

class RouteBusinessBackend extends BusinessBackend
    implements RequiredSessionBackend, ProgressiveReadBackend {
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    if (feature == FeatureId.grades && authError != null) throw authError!;
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: 'fixture-user'),
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => throw StateError('禁止提交密码');
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
}
