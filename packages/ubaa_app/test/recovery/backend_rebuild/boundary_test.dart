import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../startup_test.dart' as support;
import 'fakes.dart';

void main() {
  for (final lateQuery in [false, true]) {
    test('重建${lateQuery ? "中新增查询" : "前已发送查询"}按精确范围交给新实例，迟到旧结果不发布', () async {
      final first = QueryBackend();
      final next = QueryBackend();
      final controller = AppController(
        backend: first,
        backendFactory: () => next,
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await cachedHome(controller, first);
      await controller.recoverSession(refreshHomeAfter: false);
      const query = FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: 'synthetic',
        week: 3,
      );
      first.queryGate = Completer<FeatureResult>();
      Future<void>? reading;
      if (!lateQuery) {
        reading = controller.refreshFeatureQuery(FeatureId.schedule, query);
        await Future<void>.delayed(Duration.zero);
        expect(first.queries.length, 1);
      }
      first.dead = true;
      first.disposeGate = Completer<void>();
      final recovering = controller.resumeSession();
      await first.disposeStarted.future;
      if (lateQuery)
        reading = controller.refreshFeatureQuery(FeatureId.schedule, query);
      first.disposeGate!.complete();
      await recovering;
      first.queryGate!.complete(
        const FeatureResult.success(details: [FeatureDetail(title: '旧实例迟到结果')]),
      );
      await reading;
      await Future<void>.delayed(Duration.zero);
      expect(next.queries, hasLength(1));
      expect(
        FeatureReadContext(
          query: next.queries.single,
          requestRevision: 0,
        ).hasSameQuery(query),
        isTrue,
      );
      expect(first.queries.length, lateQuery ? 0 : 1);
      expect(
        controller.snapshots[FeatureId.schedule]!.details.single.title,
        '继任实例的新查询',
      );
      expect(
        controller.snapshots[FeatureId.schedule]!.readContext?.query?.week,
        3,
      );
    });
  }

  for (final same in [false, true]) {
    test('工厂${same ? "返回原对象" : "创建失败"}保留缓存并允许原位重试', () async {
      final first = Backend()..dead = true;
      final controller = AppController(
        backend: first,
        backendFactory: () => same ? first : throw StateError('合成本地故障'),
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await cachedHome(controller, first);
      await controller.resumeSession();
      expect(first.disposed, 0);
      expect(controller.phase, AppPhase.home);
      expect(controller.isRebuildingBackend, isFalse);
      expect(controller.error?.code, UbaaErrorCode.internalError);
      expect(
        controller.homeSnapshots[FeatureId.schedule]!.details.single.title,
        '合成缓存课程',
      );
    });
  }

  test('显式重建本地首页后自动重新检查继任会话', () async {
    final first = Backend();
    final next = Backend()..gate = Completer<AuthStatus>();
    final controller = AppController(
      backend: first,
      backendFactory: () => next,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await cachedHome(controller, first);
    controller.onHomeFirstFrame();
    await controller.recoverSession(refreshHomeAfter: false);

    expect(await controller.rebuildBackend(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(next.authCalls, 1);
    next.gate!.complete(AuthStatus.signedIn);
    for (
      var i = 0;
      i < 20 && controller.sessionRecoveryStatus != SessionRecoveryStatus.ready;
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(controller.phase, AppPhase.home);
  });

  test('继任会话属于另一账号时关闭旧缓存入口，不接纳新身份', () async {
    final first = Backend()..dead = true;
    final next = Backend()..username = 'another-fixture';
    final accounts = await support.savedAccounts();
    final controller = AppController(
      backend: first,
      backendFactory: () => next,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await cachedHome(controller, first);
    await controller.resumeSession();
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
    expect((await accounts.read())?.canRestore, isFalse);
  });

  test('失效错误返回时已在后台不新建客户端，回前台后合并恢复', () async {
    final first = Backend()..gate = Completer<AuthStatus>();
    var created = 0;
    final controller = AppController(
      backend: first,
      backendFactory: () {
        created++;
        return Backend();
      },
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await cachedHome(controller, first);
    final recovering = controller.resumeSession();
    controller.setAppForeground(false);
    first.gate!.completeError(
      const BackendException(UbaaErrorCode.internalError, clientDisposed: true),
    );
    await recovering;
    expect(created, 0);
    first.gate = null;
    first.dead = true;
    controller.setAppForeground(true);
    await controller.resumeSession();
    expect(created, 1);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
  });
}
