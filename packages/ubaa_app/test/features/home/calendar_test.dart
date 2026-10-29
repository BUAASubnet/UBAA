import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/controller/fakes.dart';
import 'package:ubaa_test_support/recovery.dart' as recovery;

void main() {
  test('不完整周次索引不能推导单日课表', () async {
    final backend = CalendarBackend()..incompleteWeeks = true;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(
      (await controller.loadHomeDaySchedule('2026-10-26')).error,
      isNotNull,
    );
    expect(
      backend.queries.where((q) => q.view == FeatureQueryView.scheduleWeek),
      isEmpty,
    );
  });

  for (final invalid in ['正常', '账号', '路线', '查询', '完整度']) {
    test('单日课表优先完整本地数据并拒绝$invalid范围混用', () async {
      final backend = CalendarCachedBackend(invalid);
      final accounts = await recovery.savedAccounts();
      backend.owner = (await accounts.read())!.account!.id;
      final controller = AppController(
        backend: backend,
        localAccountStore: accounts,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession(refreshHomeAfter: false);
      await controller.setRoutePolicy(RoutePolicy.direct);
      backend.queries.clear();
      final result = await controller.loadHomeDaySchedule('2026-10-26');
      expect(result.details.single.title, invalid == '正常' ? '本地课程' : '周一课程');
      expect(
        backend.queries
            .where((q) => q.view == FeatureQueryView.scheduleWeek)
            .length,
        invalid == '正常' ? 0 : 1,
      );
      if (invalid == '正常') {
        final refreshed = await controller.loadHomeDaySchedule(
          '2026-10-26',
          forceRefresh: true,
        );
        expect(refreshed.details.single.title, '周一课程');
      }
    });
  }

  test('跨周读取明日课程，按日期合并请求且不覆盖首页或领域快照', () async {
    final backend = CalendarBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome();
    final before = controller.homeSnapshots[FeatureId.schedule];
    final a = controller.loadHomeDaySchedule('2026-10-26');
    final b = controller.loadHomeDaySchedule('2026-10-26');
    final result = await a;
    expect(await b, same(result));
    expect(backend.queries.map((q) => q.view), [
      FeatureQueryView.scheduleTerms,
      FeatureQueryView.scheduleWeeks,
      FeatureQueryView.scheduleWeek,
    ]);
    expect(backend.queries.last.week, 8);
    expect(result.details.single.title, '周一课程');
    expect((result.overview! as HomeScheduleOverview).week.number, 8);
    expect(controller.homeSnapshots[FeatureId.schedule], same(before));
    expect(await controller.loadHomeDaySchedule('2026-10-26'), same(result));
    expect(backend.queries.length, 3);
    final next = await controller.loadHomeDaySchedule('2026-10-27');
    expect(next.details.single.title, '周二课程');
  });
  test('无覆盖周和非法日期不猜周次，失败不返回空课表成功', () async {
    final backend = CalendarBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(
      (await controller.loadHomeDaySchedule('2026-02-30')).error,
      isNotNull,
    );
    expect(backend.queries, isEmpty);
    expect(
      (await controller.loadHomeDaySchedule('2026-12-01')).error,
      isNotNull,
    );
    expect(
      backend.queries.where((q) => q.view == FeatureQueryView.scheduleWeek),
      isEmpty,
    );
  });
  test('退出后拒绝迟到课表，失败可强制重试', () async {
    final backend = CalendarBackend()..gate = Completer<FeatureResult>();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final pending = controller.loadHomeDaySchedule('2026-10-26');
    await backend.weekStarted.future;
    await controller.logout();
    backend.gate!.complete(const FeatureResult.empty());
    expect((await pending).error?.code, UbaaErrorCode.operationConflict);
  });
  test('不完整周结果不判明日无课', () async {
    final backend = CalendarBackend()..incomplete = true;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(
      (await controller.loadHomeDaySchedule('2026-10-26')).error,
      isNotNull,
    );
    backend.incomplete = false;
    expect(
      (await controller.loadHomeDaySchedule(
        '2026-10-26',
        forceRefresh: true,
      )).details.single.title,
      '周一课程',
    );
  });
}

class CalendarBackend extends FixtureQueryBackend {
  CalendarBackend() : super(onQuery: (_, _) => const FeatureResult.empty());
  final queries = <FeatureQuery>[];
  final weekStarted = Completer<void>();
  Completer<FeatureResult>? gate;
  bool incomplete = false;
  bool incompleteWeeks = false;
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-calendar');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add(query);
    if (query.view == FeatureQueryView.scheduleTerms)
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '学期',
            presentation: TermPresentation(
              code: 'term',
              selected: true,
              index: 1,
            ),
          ),
        ],
      );
    if (query.view == FeatureQueryView.scheduleWeeks)
      return FeatureResult.success(
        evidence: incompleteWeeks
            ? DataEvidence(
                accountId: 'synthetic-calendar',
                origin: DataOrigin.online,
                fetchedAt: DateTime.now(),
                complete: false,
                savedForOffline: false,
              )
            : null,
        details: [
          for (final n in [7, 8])
            FeatureDetail(
              title: '周',
              presentation: WeekPresentation(
                requestTerm: 'term',
                responseTerm: 'term',
                number: n,
                current: n == 7,
                startDate: n == 7 ? '2026-10-19' : '2026-10-26',
                endDate: n == 7 ? '2026-10-25' : '2026-11-01',
              ),
            ),
        ],
      );
    if (!weekStarted.isCompleted) weekStarted.complete();
    if (gate != null) return gate!.future;
    return FeatureResult.success(
      details: const [
        FeatureDetail(
          title: '周一课程',
          presentation: ScheduleCoursePresentation(
            courseCode: 'a',
            dayOfWeek: 1,
            beginTime: '08:00',
            endTime: '09:35',
          ),
        ),
        FeatureDetail(
          title: '周二课程',
          presentation: ScheduleCoursePresentation(
            courseCode: 'b',
            dayOfWeek: 2,
            beginTime: '09:50',
            endTime: '12:15',
          ),
        ),
      ],
      evidence: incomplete
          ? DataEvidence(
              accountId: 'synthetic-calendar',
              origin: DataOrigin.online,
              fetchedAt: DateTime.now(),
              complete: false,
              savedForOffline: false,
            )
          : null,
    );
  }
}

class CalendarCachedBackend extends CalendarBackend
    implements OfflineQueryBackend {
  CalendarCachedBackend(this.invalid);
  final String invalid;
  late String owner;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-user');
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    final weekly = query.view == FeatureQueryView.scheduleWeek;
    return OfflineQueryRead(
      CachedFeatureProjection(
        feature: feature,
        accountId: weekly && invalid == '账号' ? 'other' : owner,
        route: weekly && invalid == '路线'
            ? ConnectionMode.webvpn
            : ConnectionMode.direct,
        complete: !(weekly && invalid == '完整度'),
        fetchedAt: DateTime(2026, 10, 25),
        query: weekly && invalid == '查询' ? query.copyWith(week: 99) : query,
        details: switch (query.view) {
          FeatureQueryView.scheduleTerms => const [
            FeatureDetail(
              title: '学期',
              presentation: TermPresentation(
                code: 'term',
                selected: true,
                index: 1,
              ),
            ),
          ],
          FeatureQueryView.scheduleWeeks => const [
            FeatureDetail(
              title: '周',
              presentation: WeekPresentation(
                requestTerm: 'term',
                responseTerm: 'term',
                number: 8,
                current: false,
                startDate: '2026-10-26',
                endDate: '2026-11-01',
              ),
            ),
          ],
          _ => const [
            FeatureDetail(
              title: '本地课程',
              presentation: ScheduleCoursePresentation(
                courseCode: 'cached',
                dayOfWeek: 1,
                beginTime: '08:00',
                endTime: '09:35',
              ),
            ),
          ],
        },
      ),
    );
  }
}
