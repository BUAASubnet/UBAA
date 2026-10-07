import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';

void main() {
  testWidgets('本地缓存故障在首页及作业页独立提示且保留在线内容', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, date: '2026-09-21', cacheFailure: true);
    expect(find.textContaining('在线内容已显示，暂未保存到本机'), findsOneWidget);
    expect(find.textContaining('希冀：刷新失败'), findsNothing);
    await openFeature(tester, FeatureId.judge);
    expect(find.textContaining('在线内容已显示，暂未保存到本机'), findsOneWidget);
    expect(find.text('合成在线作业'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('博雅补充读取失败仍显示已保存待办', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, date: '2026-09-21', empty: true, failSupplement: true);
    expect(find.text('缓存博雅待办'), findsOneWidget);
    expect(find.text('缓存研讨室待办'), findsOneWidget);
    expect(find.textContaining('博雅：上次保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页已选博雅缓存不被尚未返回的补充来源清空', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, date: '2026-09-21', empty: true);
    expect(find.text('缓存博雅待办'), findsOneWidget);
    expect(find.text('缓存研讨室待办'), findsOneWidget);
    expect(find.textContaining('博雅：上次保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页部分在线来源不能标成刷新失败和上次结果', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, date: '2026-09-21', partial: true);
    expect(find.textContaining('希冀：部分内容尚未更新完成'), findsOneWidget);
    expect(find.textContaining('希冀：刷新失败'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('已保存的空课表不能冒充刚刚确认的今日无课', (tester) async {
    await mount(tester, date: '2026-09-21', empty: true);
    expect(find.text('上次保存时没有课程安排'), findsOneWidget);
    expect(find.textContaining('上次保存：'), findsOneWidget);
    expect(find.text('今天没有课程安排'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('已保存待办标明保存依据，不误称刚发生刷新失败', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, date: '2026-09-21', empty: true);
    expect(find.textContaining('希冀：上次保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('跨校园午夜后不把昨日缓存课程放在今日下', (tester) async {
    await mount(tester, date: '2026-09-20');
    expect(find.text('昨日合成课程'), findsNothing);
    expect(find.text('尚无今天保存的课表'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> mount(
  WidgetTester tester, {
  required String date,
  bool empty = false,
  bool partial = false,
  bool failSupplement = false,
  bool cacheFailure = false,
}) async {
  await withClock(Clock.fixed(DateTime.utc(2026, 9, 20, 16, 5)), () async {
    await tester.pumpWidget(
      MaterialApp(
        home: UbaaMainShell(
          homeClock: clock,
          user: const UserSummary(username: 'synthetic'),
          snapshots: {
            for (final id in FeatureId.values) id: FeatureSnapshot(feature: id),
            FeatureId.cgyy: CachedFeatureProjection(
              feature: FeatureId.cgyy,
              query: const FeatureQuery(view: FeatureQueryView.cgyyOrders),
              accountId: 'synthetic',
              route: ConnectionMode.direct,
              fetchedAt: DateTime.utc(2026, 9, 20, 15),
              complete: true,
              details: const [
                FeatureDetail(
                  title: '缓存研讨室待办',
                  presentation: CgyyOrderPresentation(
                    id: 9,
                    statusText: '审批通过',
                    venueName: '缓存研讨室待办',
                    reservationStartDate: '2026-09-21 09:00:00',
                    reservationEndDate: '2026-09-21 10:00:00',
                    orderStatus: 1,
                    checkStatus: 1,
                  ),
                ),
              ],
            ).toSnapshot(),
            FeatureId.bykc: CachedFeatureProjection(
              feature: FeatureId.bykc,
              query: const FeatureQuery(
                view: FeatureQueryView.bykcChosenCourses,
              ),
              accountId: 'synthetic',
              route: ConnectionMode.direct,
              fetchedAt: DateTime.utc(2026, 9, 20, 15),
              complete: true,
              details: const [
                FeatureDetail(
                  title: '缓存博雅待办',
                  presentation: BykcChosenPresentation(
                    recordId: 1,
                    courseId: 42,
                    courseName: '缓存博雅待办',
                    courseStartDate: '2026-09-21 08:00:00',
                    courseEndDate: '2026-09-21 10:00:00',
                  ),
                ),
              ],
            ).toSnapshot(),
            FeatureId.judge: partial || cacheFailure
                ? FeatureSnapshot(
                    feature: FeatureId.judge,
                    status: cacheFailure
                        ? FeatureLoadStatus.success
                        : FeatureLoadStatus.stale,
                    details: cacheFailure
                        ? const [FeatureDetail(title: '合成在线作业')]
                        : const [],
                    evidence: DataEvidence(
                      accountId: 'synthetic',
                      origin: DataOrigin.online,
                      fetchedAt: DateTime.utc(2026, 9, 20, 15),
                      complete: cacheFailure,
                      savedForOffline: !cacheFailure,
                      cacheFailure: cacheFailure
                          ? CacheMaintenanceFailure.corrupt
                          : null,
                    ),
                  )
                : CachedFeatureProjection(
                    feature: FeatureId.judge,
                    accountId: 'synthetic',
                    route: ConnectionMode.direct,
                    fetchedAt: DateTime.utc(2026, 9, 20, 15),
                    complete: true,
                  ).toSnapshot(),
            FeatureId.schedule: CachedFeatureProjection(
              feature: FeatureId.schedule,
              accountId: 'synthetic',
              route: ConnectionMode.direct,
              fetchedAt: DateTime.utc(2026, 9, 20, 15),
              complete: true,
              scopeDate: date,
              details: empty
                  ? []
                  : const [
                      FeatureDetail(
                        title: '昨日合成课程',
                        presentation: TodayCoursePresentation(
                          time: '08:00',
                          place: '合成教室',
                        ),
                      ),
                    ],
            ).toSnapshot(),
          },
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          activeRoutes: const [],
          onLoadHomeSupplement: failSupplement
              ? (_, __) async => FeatureResult.failure(
                  const UiError(
                    code: UbaaErrorCode.networkError,
                    title: '网络不可用',
                    message: '合成失败',
                  ),
                )
              : null,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}
