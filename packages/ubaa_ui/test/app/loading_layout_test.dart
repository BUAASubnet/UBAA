import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/common/feature_detail.dart';
import 'package:ubaa_ui/src/features/grades/flow.dart';
import 'package:ubaa_ui/src/app/home.dart';
import 'package:ubaa_ui/src/shared/loading.dart';

void main() {
  testWidgets('首页来源逐一结束不会移动已显示的待办', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> mount(FeatureLoadStatus status) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeView(
            user: null,
            visible: true,
            cacheEpoch: 0,
            homeClock: Clock.fixed(DateTime(2026, 10, 20)),
            snapshots: {
              for (final f in FeatureId.values)
                f: FeatureSnapshot(feature: f, status: status),
              FeatureId.schedule: FeatureSnapshot(
                feature: FeatureId.schedule,
                status: status,
                updatedAt: DateTime(2026, 10, 20),
              ),
              FeatureId.spoc: const FeatureSnapshot(
                feature: FeatureId.spoc,
                status: FeatureLoadStatus.success,
                details: [
                  FeatureDetail(
                    title: '合成待办',
                    presentation: SpocAssignmentPresentation(
                      courseId: 'c',
                      courseName: '合成课程',
                      assignmentId: 'a',
                      dueTime: '2026-10-21 12:00:00',
                      status: AssignmentSubmissionStatus.unsubmitted,
                      statusText: '未提交',
                    ),
                  ),
                ],
              ),
            },
            onLoadSupplement: (_, _) async => const FeatureResult.empty(),
            onFeatureTap: (_) {},
            onRetryFeature: (_) async {},
            onRefresh: () async {},
            onTodoTap: (_) {},
          ),
        ),
      ),
    );
    await mount(FeatureLoadStatus.loading);
    await tester.pump();
    final before = tester.getTopLeft(find.text('合成待办'));
    await mount(FeatureLoadStatus.empty);
    expect(tester.getTopLeft(find.text('合成待办')), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('刷新按钮保留尺寸且同一请求未结束不能重复触发', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefreshActionButton(
            tooltip: '刷新合成列表',
            onRefresh: () {
              calls++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    final target = find.byType(IconButton);
    final before = tester.getRect(target);
    await tester.tap(target);
    await tester.pump();
    expect(tester.getRect(target), before);
    await tester.tap(target);
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(target).onPressed, isNotNull);
  });

  testWidgets('刷新中的旧写入按钮原位禁用，新结果返回后恢复', (tester) async {
    var writes = 0;
    const ready = FeatureSnapshot(
      feature: FeatureId.signin,
      status: FeatureLoadStatus.success,
      details: [
        FeatureDetail(
          title: '合成签到课程',
          actions: [
            SigninPerformAction(
              scheduleId: 's',
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
        FeatureDetail(title: '下方内容'),
      ],
    );
    Future<void> mount(FeatureSnapshot snapshot) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureDetailView(
            feature: FeatureId.signin,
            snapshot: snapshot,
            bykcFilters: const BykcCourseFilters.defaults(),
            onBykcFiltersChanged: (_) {},
            onBack: () {},
            onRetry: () async {},
            onSigninWrite: (_) async {
              writes++;
            },
          ),
        ),
      ),
    );
    await mount(ready);
    final button = find.widgetWithText(OutlinedButton, '签到');
    final before = tester.getTopLeft(find.text('下方内容'));
    await mount(ready.copyWith(status: FeatureLoadStatus.loading));
    expect(tester.getTopLeft(find.text('下方内容')), before);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(writes, 0);
    await mount(ready);
    await tester.tap(button);
    expect(writes, 1);
  });

  testWidgets('连接恢复结束不移动首页内容，登录入口仍可用', (tester) async {
    var logins = 0;
    Future<void> mount(String? status, {bool login = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: UbaaMainShell(
              user: const UserSummary(username: 'synthetic'),
              snapshots: {
                for (final f in FeatureId.values)
                  f: FeatureSnapshot(
                    feature: f,
                    status: FeatureLoadStatus.empty,
                  ),
              },
              routePolicy: RoutePolicy.auto,
              telemetryEnabled: false,
              connectionStatus: status,
              onCompleteLogin: login
                  ? (_) async {
                      logins++;
                    }
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
    await mount('正在连接，稍后更新内容');
    final before = tester.getTopLeft(find.text('今日课表'));
    await mount(null);
    expect(tester.getTopLeft(find.text('今日课表')), before);
    await mount('需要登录，当前页面会保留', login: true);
    expect(tester.getTopLeft(find.text('今日课表')), before);
    await tester.tap(find.byTooltip('完成登录'));
    expect(logins, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('同查询刷新保留列表位置，换查询空快照不冒用旧结果', (tester) async {
    final ready = FeatureSnapshot(
      feature: FeatureId.signin,
      status: FeatureLoadStatus.success,
      details: [for (var i = 0; i < 40; i++) FeatureDetail(title: '合成记录 $i')],
    );
    Future<void> mount(FeatureSnapshot snapshot) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureDetailView(
            feature: FeatureId.signin,
            snapshot: snapshot,
            bykcFilters: const BykcCourseFilters.defaults(),
            onBykcFiltersChanged: (_) {},
            onBack: () {},
            onRetry: () async {},
          ),
        ),
      ),
    );
    // 列表上方的搜索框自带横向滚动，这里只取纵向结果列表。
    final list = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    await mount(ready);
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    final anchor = find.text('合成记录 8');
    final before = tester.getTopLeft(anchor);
    final scroll = tester.state<ScrollableState>(list);
    final offset = scroll.position.pixels;
    await mount(ready.copyWith(status: FeatureLoadStatus.loading));
    expect(anchor, findsOneWidget);
    expect(tester.getTopLeft(anchor), before);
    expect(scroll.position.pixels, offset);
    await mount(ready);
    expect(tester.getTopLeft(anchor), before);
    await mount(
      const FeatureSnapshot(
        feature: FeatureId.signin,
        status: FeatureLoadStatus.loading,
      ),
    );
    expect(anchor, findsNothing);
    await mount(
      const FeatureSnapshot(
        feature: FeatureId.signin,
        status: FeatureLoadStatus.empty,
      ),
    );
    expect(find.text('暂无课堂签到数据'), findsOneWidget);
    final emptyPosition = tester.getTopLeft(find.text('暂无课堂签到数据'));
    await mount(
      FeatureSnapshot(
        feature: FeatureId.signin,
        status: FeatureLoadStatus.loading,
        updatedAt: DateTime(2026, 10, 20),
      ),
    );
    expect(tester.getTopLeft(find.text('暂无课堂签到数据')), emptyPosition);
  });

  testWidgets('成绩分期返回与同查询刷新不推移统计卡', (tester) async {
    final pending = Completer<GradesAggregate>();
    const overview = GradesTermOverview(
      requestTerm: 'a',
      termCode: 'a',
      grades: [],
    );
    const ready = FeatureSnapshot(
      feature: FeatureId.grades,
      status: FeatureLoadStatus.success,
      overview: overview,
    );
    Future<void> mount(FeatureSnapshot snapshot) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GradesFlow(
            snapshot: snapshot,
            visible: true,
            cacheEpoch: 0,
            filter: '',
            fallback: const Text('占位'),
            loader: (_, _) => pending.future,
          ),
        ),
      ),
    );
    await mount(ready);
    await tester.pump();
    final before = tester.getTopLeft(find.text('本学期'));
    pending.complete(
      const GradesAggregate(
        terms: [
          GradeTermRead(
            code: 'a',
            name: '甲学期',
            result: FeatureResult.success(overview: overview),
          ),
          GradeTermRead(
            code: 'b',
            name: '乙学期',
            result: FeatureResult.success(
              overview: GradesTermOverview(
                requestTerm: 'b',
                termCode: 'b',
                grades: [],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('本学期')), before);
    await mount(ready.copyWith(status: FeatureLoadStatus.loading));
    expect(tester.getTopLeft(find.text('本学期')), before);
  });
}
