import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart';
import '../support/controller/clock_accounts.dart';

void main() {
  for (final empty in [false, true]) {
    test('认证前恢复实际展示的明日课表，空课表=$empty', () async {
      final backend = _Backend()..emptyDay = empty;
      final controller = AppController(
        backend: backend,
        localAccountStore: ClockAccounts(),
      );
      controller.attachHomePresentation();
      addTearDown(controller.dispose);
      await controller.initialize();
      final day = controller.homeState.schedule;
      expect(day.tomorrow, isTrue);
      expect(day.snapshot.evidence?.origin, DataOrigin.persisted);
      expect(day.snapshot.evidence?.complete, isTrue);
      expect(day.snapshot.details.map((d) => d.title), empty ? [] : ['缓存明日课程']);
      expect(day.snapshot.updatedAt, backend.fetched);
      expect(backend.authCalls, 0);
      expect(backend.readCalls, 0);
    });
  }
  test('缓存首屏同时带待办与按今天日期确定的周次，认证尚未发送', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: ClockAccounts(),
    );
    controller.attachHomePresentation(visible: false);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.homeState.todos.single.title, '缓存考试');
    expect(
      controller.homeState.week!.details.single.presentation,
      isA<WeekPresentation>(),
    );
    expect(
      (controller.homeState.week!.details.single.presentation
              as WeekPresentation)
          .number,
      10,
    );
    expect(backend.authCalls, 0);
    expect(backend.readCalls, 0);
    expect(backend.policies, everyElement(RoutePolicy.webvpn));
    expect(
      controller.homeState.sources[FeatureId.exam]!.evidence!.origin,
      DataOrigin.persisted,
    );
  });
}

class _Backend extends FakeRecoveryBackend
    implements
        OfflineCacheBackend,
        OfflineQueryBackend,
        HomeTodoBackend,
        RouteSettingsBackend {
  final policies = <RoutePolicy>[];
  bool emptyDay = false;
  @override
  Future<BackendRouteSettings> routeSettings() async =>
      const BackendRouteSettings(
        defaultPolicy: RoutePolicy.webvpn,
        activeRoutes: [ConnectionMode.webvpn],
      );
  LocalAccount? account;
  final fetched = DateTime.now().subtract(const Duration(minutes: 10));
  @override
  Future<void> openOfflineAccount(LocalAccount value, List<int> key) async {
    account = value;
  }

  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> clearOfflineAccount({required String accountId}) async {}
  CachedFeatureProjection cached(
    FeatureId feature,
    List<FeatureDetail> rows, {
    FeatureQuery? query,
  }) => CachedFeatureProjection(
    feature: feature,
    accountId: account!.id,
    route: ConnectionMode.webvpn,
    fetchedAt: fetched,
    complete: true,
    details: rows,
    query: query,
  );
  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead([
        cached(FeatureId.exam, const [FeatureDetail(title: '缓存考试')]),
        cached(FeatureId.schedule, const []),
      ]);
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    policies.add(policy);
    if (query.view == FeatureQueryView.scheduleWeeks) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    final today = homeCampusTime(DateTime.now());
    if (query.view == FeatureQueryView.scheduleWeek) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return OfflineQueryRead(
        cached(
          feature,
          emptyDay
              ? []
              : [
                  FeatureDetail(
                    title: '缓存明日课程',
                    presentation: ScheduleCoursePresentation(
                      courseCode: 'cached',
                      dayOfWeek: DateTime(
                        today.year,
                        today.month,
                        today.day + 1,
                      ).weekday,
                      beginTime: '08:00',
                      endTime: '09:35',
                    ),
                  ),
                ],
          query: query,
        ),
      );
    }
    return OfflineQueryRead(
      cached(
        feature,
        query.view == FeatureQueryView.scheduleTerms
            ? const [
                FeatureDetail(
                  title: '学期',
                  presentation: TermPresentation(
                    code: 'term',
                    selected: true,
                    index: 0,
                  ),
                ),
              ]
            : [
                FeatureDetail(
                  title: '周',
                  presentation: WeekPresentation(
                    requestTerm: 'term',
                    responseTerm: 'term',
                    number: 10,
                    current: false,
                    startDate: homeDateKey(
                      today.subtract(const Duration(days: 2)),
                    ),
                    endDate: homeDateKey(today.add(const Duration(days: 4))),
                  ),
                ),
              ],
        query: query,
      ),
    );
  }

  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) async =>
      HomeTodoProjection([
        for (final row
            in request.snapshots[FeatureId.exam]?.details ?? <FeatureDetail>[])
          HomeTodo(
            id: row.title,
            feature: FeatureId.exam,
            title: row.title,
            subtitle: '',
            statusLabel: '',
            timeLabel: '',
            sortTime: request.now,
          ),
      ]);
}
