import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../../cache/query_test.dart' show until;

const _week = FeatureQuery(
  view: FeatureQueryView.scheduleWeek,
  term: '20261',
  week: 1,
);

void main() {
  Future<AppController> setup(_Backend backend) async {
    final accounts = await support.savedAccounts();
    backend.accountId = (await accounts.read())!.account!.id;
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    return controller;
  }

  for (final empty in [false, true]) {
    test('切换${empty ? '空周' : '有课周'}直接展示完整缓存，不进入加载或在线读取', () async {
      final backend = _Backend()..empty = empty;
      final controller = await setup(backend);
      final notifications = <FeatureSnapshot>[];
      controller.addListener(() {
        notifications.add(controller.snapshots[FeatureId.schedule]!);
      });
      final authCalls = backend.authCalls;
      await controller.refreshFeatureQuery(FeatureId.schedule, _week);
      await controller.refreshFeatureQuery(
        FeatureId.schedule,
        _week.copyWith(week: 2),
      );
      expect(backend.online, isEmpty);
      expect(backend.authCalls, authCalls);
      expect(
        notifications.where((s) => s.status == FeatureLoadStatus.loading),
        isEmpty,
      );
      final snapshot = controller.snapshots[FeatureId.schedule]!;
      expect(
        snapshot.status,
        empty ? FeatureLoadStatus.empty : FeatureLoadStatus.success,
      );
      expect(snapshot.readContext!.query!.week, 2);
      expect(snapshot.evidence!.origin, DataOrigin.persisted);
      expect(snapshot.updatedAt, backend.fetched);
      if (!empty) expect(snapshot.details.single.title, '缓存第2周');
    });
  }

  test('同周明确刷新继续请求网络', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    await controller.refreshFeatureQuery(FeatureId.schedule, _week);
    backend.online.clear();
    await controller.refreshFeatureQuery(FeatureId.schedule, _week);
    expect(backend.online.single.hasSameParameters(_week), isTrue);
    expect(
      controller.snapshots[FeatureId.schedule]!.details.single.title,
      '在线课表',
    );
  });

  for (final missing in ['缺失', '不完整', '账号', '查询']) {
    test('$missing缓存继续在线读取', () async {
      final backend = _Backend()..invalid = missing;
      final controller = await setup(backend);
      await controller.refreshFeatureQuery(FeatureId.schedule, _week);
      expect(backend.online.single.hasSameParameters(_week), isTrue);
      expect(
        controller.snapshots[FeatureId.schedule]!.details.single.title,
        '在线课表',
      );
    });
  }

  test('本地周课表超过预读时限仍等待缓存，迟到结果不覆盖新周', () async {
    final backend = _Backend()..pending = Completer<OfflineQueryRead>();
    final controller = await setup(backend);
    final first = controller.refreshFeatureQuery(FeatureId.schedule, _week);
    await until(() => backend.reads.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(backend.online, isEmpty);
    final pending = backend.pending!;
    backend.pending = null;
    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      _week.copyWith(week: 2),
    );
    pending.complete(OfflineQueryRead(backend.projection(_week)));
    await first;
    expect(
      controller.snapshots[FeatureId.schedule]!.readContext!.query!.week,
      2,
    );
  });

  test('日期与周次选项从完整缓存读取，主动刷新仍联网', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    final before = controller.snapshots[FeatureId.schedule];
    final result = await controller.loadAcademicWeeks('20261');
    expect(backend.online, isEmpty);
    expect(result.evidence!.origin, DataOrigin.persisted);
    final week = result.details.single.presentation! as WeekPresentation;
    expect(week.headerDateLabels, [
      '9-7',
      '9-8',
      '9-9',
      '9-10',
      '9-11',
      '9-12',
      '9-13',
    ]);
    expect(controller.snapshots[FeatureId.schedule], same(before));
    await controller.loadAcademicWeeks('20261', forceRefresh: true);
    expect(backend.online.single.view, FeatureQueryView.scheduleWeeks);
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements OfflineQueryBackend, FeatureQueryBackend {
  String accountId = '';
  bool empty = false;
  String? invalid;
  final fetched = DateTime.utc(2026, 11, 13);
  final online = <FeatureQuery>[];
  final reads = <FeatureQuery>[];
  Completer<OfflineQueryRead>? pending;

  CachedFeatureProjection projection(FeatureQuery query) =>
      CachedFeatureProjection(
        feature: FeatureId.schedule,
        accountId: invalid == '账号' ? 'other' : accountId,
        route: ConnectionMode.webvpn,
        fetchedAt: fetched,
        complete: invalid != '不完整',
        query: invalid == '查询' ? query.copyWith(week: 9) : query,
        details: query.view == FeatureQueryView.scheduleWeeks
            ? const [
                FeatureDetail(
                  title: '第1周',
                  presentation: WeekPresentation(
                    requestTerm: '20261',
                    responseTerm: '20261',
                    number: 1,
                    current: true,
                    startDate: '2026-09-07',
                    endDate: '2026-09-13',
                  ),
                ),
              ]
            : empty
            ? const []
            : [FeatureDetail(title: '缓存第${query.week}周')],
      );

  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    reads.add(query);
    return pending?.future ??
        OfflineQueryRead(invalid == '缺失' ? null : projection(query));
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    online.add(query);
    return const FeatureResult.success(
      details: [FeatureDetail(title: '在线课表')],
      resolvedRoute: ConnectionMode.direct,
    );
  }
}
