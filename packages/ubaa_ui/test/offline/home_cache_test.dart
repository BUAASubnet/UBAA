import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
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
}) async {
  await withClock(Clock.fixed(DateTime.utc(2026, 9, 20, 16, 5)), () async {
    await tester.pumpWidget(
      MaterialApp(
        home: UbaaMainShell(
          user: const UserSummary(username: 'synthetic'),
          snapshots: {
            for (final id in FeatureId.values) id: FeatureSnapshot(feature: id),
            FeatureId.judge: partial
                ? FeatureSnapshot(
                    feature: FeatureId.judge,
                    status: FeatureLoadStatus.stale,
                    evidence: DataEvidence(
                      accountId: 'synthetic',
                      origin: DataOrigin.online,
                      fetchedAt: DateTime.utc(2026, 9, 20, 15),
                      complete: false,
                      savedForOffline: true,
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
