import 'dart:async';
import 'package:clock/clock.dart';
import 'package:ubaa_ui/src/features/home/schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/home.dart';

void main() {
  testWidgets('明日课表路线反映实际日程来源，午夜后保留同日路线', (tester) async {
    final routes = <HomeScheduleRoute>[];
    Future<FeatureResult> read(String date, bool force) async =>
        dayResult(date, '明日课程', route: ConnectionMode.webvpn);
    await calendar(
      tester,
      DateTime(2026, 10, 25, 20),
      read,
      onRoute: routes.add,
    );
    expect(routes.last, (label: '明日课表', route: ConnectionMode.webvpn));
    await calendar(tester, DateTime(2026, 10, 26), read, onRoute: routes.add);
    expect(routes.last, (label: '今日课表', route: ConnectionMode.webvpn));
  });

  testWidgets('最后一节结束才读取明日，周日跨周与午夜保持日期归属', (tester) async {
    final requests = <String>[];
    Future<FeatureResult> read(String date, bool force) async {
      requests.add(date);
      return dayResult(date, '周一课程');
    }

    await calendar(tester, DateTime(2026, 10, 25, 12, 14), read);
    expect(find.text('进行中'), findsOneWidget);
    expect(requests, isEmpty);
    await calendar(tester, DateTime(2026, 10, 25, 12, 15), read);
    expect(find.text('明日课表'), findsOneWidget);
    expect(find.text('周一课程'), findsOneWidget);
    expect(find.textContaining('第8周'), findsOneWidget);
    expect(find.text('今日课程'), findsNothing);
    await calendar(tester, DateTime(2026, 10, 26), read);
    expect(find.text('今日课表'), findsOneWidget);
    expect(find.text('周一课程'), findsOneWidget);
    expect(requests, ['2026-10-26']);
  });
  testWidgets('未知时间与今日无课不触发明日读取', (tester) async {
    var calls = 0;
    Future<FeatureResult> read(String date, bool force) async {
      calls++;
      return dayResult(date, '不应读取');
    }

    await calendar(tester, DateTime(2026, 10, 25, 20), read, time: '09:50-待定');
    expect(find.text('时间待定'), findsOneWidget);
    expect(calls, 0);
    await calendar(tester, DateTime(2026, 10, 25, 20), read, empty: true);
    expect(find.text('今日课表'), findsOneWidget);
    expect(calls, 0);
  });
  testWidgets('迟到的明日响应不覆盖午夜后的新目标，错误日期拒绝显示', (tester) async {
    final gate = Completer<FeatureResult>();
    Future<FeatureResult> read(String date, bool force) async =>
        date == '2026-10-26' ? gate.future : dayResult('2026-10-28', '错误日期课程');
    await calendar(tester, DateTime(2026, 10, 25, 20), read, settle: false);
    await calendar(tester, DateTime(2026, 10, 27), read, settle: false);
    gate.complete(dayResult('2026-10-26', '旧日期课程'));
    await tester.pumpAndSettle();
    expect(find.text('旧日期课程'), findsNothing);
    expect(find.text('错误日期课程'), findsNothing);
    expect(find.text('课表日期未确认'), findsOneWidget);
  });
  testWidgets('刷新失败保留同日期课表，重试携带强制刷新', (tester) async {
    var fail = false;
    final forces = <bool>[];
    Future<FeatureResult> read(String date, bool force) async {
      forces.add(force);
      return fail
          ? const FeatureResult.failure(
              UiError(
                code: UbaaErrorCode.networkError,
                title: '失败',
                message: '合成网络失败',
              ),
            )
          : dayResult(date, '缓存课程');
    }

    await calendar(tester, DateTime(2026, 10, 25, 20), read);
    fail = true;
    await calendar(tester, DateTime(2026, 10, 25, 20), read, epoch: 1);
    expect(find.text('缓存课程'), findsOneWidget);
    expect(find.text('合成网络失败'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(forces, [false, true, true]);
    expect(find.text('合成网络失败'), findsNothing);
  });

  testWidgets('今日课程按校园时间显示已结束状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeView(
            user: null,
            visible: true,
            cacheEpoch: 0,
            homeClock: Clock.fixed(DateTime.utc(2026, 10, 25, 6)),
            snapshots: {
              for (final f in FeatureId.values)
                f: FeatureSnapshot(
                  feature: f,
                  status: FeatureLoadStatus.success,
                  details: f == FeatureId.schedule
                      ? const [
                          FeatureDetail(
                            title: '合成课程',
                            subtitle: '课',
                            presentation: TodayCoursePresentation(
                              time: '09:50-12:15',
                              place: '教学楼',
                            ),
                          ),
                        ]
                      : const [],
                ),
            },
            onFeatureTap: (_) {},
            onRetryFeature: (_) async {},
            onRefresh: () async {},
            onTodoTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已结束'), findsOneWidget);
  });
}

FeatureResult dayResult(
  String date,
  String title, {
  ConnectionMode route = ConnectionMode.direct,
}) => FeatureResult.success(
  resolvedRoute: route,
  details: [
    FeatureDetail(
      title: title,
      presentation: const TodayCoursePresentation(time: '08:00-09:35'),
    ),
  ],
  overview: HomeScheduleOverview(
    date: date,
    week: const WeekPresentation(
      requestTerm: 'term',
      responseTerm: 'term',
      number: 8,
      current: false,
      startDate: '2026-10-26',
      endDate: '2026-11-01',
    ),
  ),
);

Future<void> calendar(
  WidgetTester tester,
  DateTime now,
  Future<FeatureResult> Function(String, bool) read, {
  String? time = '09:50-12:15',
  bool empty = false,
  bool settle = true,
  int epoch = 0,
  ValueChanged<HomeScheduleRoute>? onRoute,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HomeScheduleSection(
            today: FeatureSnapshot(
              feature: FeatureId.schedule,
              status: empty
                  ? FeatureLoadStatus.empty
                  : FeatureLoadStatus.success,
              evidence: DataEvidence(
                accountId: 'synthetic',
                origin: DataOrigin.online,
                fetchedAt: DateTime(2026, 10, 25),
                complete: true,
                savedForOffline: true,
                scopeDate: '2026-10-25',
              ),
              details: empty
                  ? []
                  : [
                      FeatureDetail(
                        title: '今日课程',
                        presentation: TodayCoursePresentation(time: time),
                      ),
                    ],
            ),
            now: now,
            visible: true,
            epoch: epoch,
            businessEpoch: 0,
            onOpenSchedule: () {},
            onLoadDay: read,
            onRoute: onRoute,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}
