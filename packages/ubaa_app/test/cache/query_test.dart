import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;

const target = FeatureQuery(
  view: FeatureQueryView.judgeDetail,
  courseId: '12',
  assignmentId: '101',
);
Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue);
}

void main() {
  test('首页状态通知中立即进入详情也等待账号缓存打开', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    var requested = false;
    controller.addListener(() {
      if (!requested && controller.phase == AppPhase.home) {
        requested = true;
        unawaited(controller.refreshFeatureQuery(FeatureId.judge, target));
      }
    });
    await controller.initialize();
    await until(
      () => controller.snapshots[FeatureId.judge]!.details.isNotEmpty,
    );
    expect(
      controller.snapshots[FeatureId.judge]!.details.single.title,
      '缓存101',
    );
    expect(controller.localCacheError, isNull);
  });

  test('晚到的磁盘详情不覆盖已成功的在线结果', () async {
    final backend = _Backend()
      ..diskGate = Completer<void>()
      ..signedIn = true;
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    await controller.refreshFeatureQuery(FeatureId.judge, target);
    expect(
      controller.snapshots[FeatureId.judge]!.details.single.title,
      '在线101',
    );
    backend.diskGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.snapshots[FeatureId.judge]!.details.single.title,
      '在线101',
    );
    expect(controller.snapshots[FeatureId.judge]!.evidence, isNull);
  });
  for (final mismatch in ['账号', '查询', '路线']) {
    test(
      mismatch == '路线' ? 'Auto 缓存保留其真实路线' : '不匹配的$mismatch缓存不进入当前页面',
      () async {
        final backend = _Backend()..mismatch = mismatch;
        final controller = AppController(
          backend: backend,
          localAccountStore: await support.savedAccounts(),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        unawaited(controller.refreshFeatureQuery(FeatureId.judge, target));
        await until(() => backend.queries.isNotEmpty);
        await Future<void>.delayed(Duration.zero);
        if (mismatch != '路线')
          expect(controller.snapshots[FeatureId.judge]!.details, isEmpty);
        // Auto 可展示任一来源，但必须保留真实来源；固定路线由 Bridge 专测。
        if (mismatch == '路线')
          expect(
            controller.snapshots[FeatureId.judge]!.resolvedRoute,
            ConnectionMode.webvpn,
          );
      },
    );
  }

  test('认证未开始时显式详情可从本地展示，失败后保留原内容时间', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final request = controller.refreshFeatureQuery(FeatureId.judge, target);
    await until(
      () => controller.snapshots[FeatureId.judge]!.details.isNotEmpty,
    );
    expect(backend.authCalls, 0);
    expect(
      controller.snapshots[FeatureId.judge]!.details.single.title,
      '缓存101',
    );
    expect(controller.snapshots[FeatureId.judge]!.updatedAt, backend.fetched);
    controller.onHomeFirstFrame();
    await request;
    expect(
      controller.snapshots[FeatureId.judge]!.details.single.title,
      '缓存101',
    );
    expect(controller.snapshots[FeatureId.judge]!.error, isNotNull);
  });
  test('迟到旧查询缓存不能覆盖新查询', () async {
    final backend = _Backend()..diskGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    unawaited(controller.refreshFeatureQuery(FeatureId.judge, target));
    await until(() => backend.queries.length == 1);
    unawaited(
      controller.refreshFeatureQuery(
        FeatureId.judge,
        target.copyWith(assignmentId: '102'),
      ),
    );
    await until(() => backend.queries.length == 2);
    backend.diskGate!.complete();
    await until(
      () => controller.snapshots[FeatureId.judge]!.details.isNotEmpty,
    );
    expect(
      controller.snapshots[FeatureId.judge]!.details.single.title,
      '缓存102',
    );
  });
}

class _Backend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        ProgressiveReadBackend,
        RequiredSessionBackend,
        OfflineCacheBackend,
        OfflineQueryBackend {
  LocalAccount? account;
  Completer<void>? diskGate;
  final fetched = DateTime.utc(2026, 9, 1);
  final queries = <FeatureQuery>[];
  int authCalls = 0;
  bool signedIn = false;
  String? mismatch;
  @override
  Future<void> openOfflineAccount(LocalAccount value, List<int> key) async {
    account = value;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead([]);
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    queries.add(query);
    await diskGate?.future;
    return OfflineQueryRead(
      CachedFeatureProjection(
        feature: feature,
        accountId: mismatch == '账号' ? '另一账号' : account!.id,
        route: mismatch == '路线' ? ConnectionMode.webvpn : ConnectionMode.direct,
        fetchedAt: fetched,
        complete: true,
        query: mismatch == '查询' ? query.copyWith(assignmentId: 'other') : query,
        details: [FeatureDetail(title: '缓存${query.assignmentId}')],
      ),
    );
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    authCalls++;
    if (signedIn)
      return const RecoveredRouteSession(
        route: ConnectionMode.direct,
        profile: UserSummary(username: 'fixture-user'),
      );
    throw const BackendException(UbaaErrorCode.networkError);
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => FeatureResult.success(
    details: [FeatureDetail(title: '在线${query.assignmentId}')],
    resolvedRoute: ConnectionMode.direct,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
