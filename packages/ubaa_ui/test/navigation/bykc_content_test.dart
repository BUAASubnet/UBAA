import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/navigation.dart';
import '../support/write_harness.dart';

void main() {
  testWidgets('博雅列表选课时间沿旧版按当前时间显示开始或截止，不由状态猜测', (tester) async {
    await _open(tester, const [
      FeatureDetail(
        title: '合成未来课程',
        presentation: BykcCoursePresentation(
          id: 1,
          courseName: '合成未来课程',
          status: BykcCourseStatus.available,
          courseSelectStartDate: '2100-01-01 08:00:00',
          courseSelectEndDate: '2100-01-02 18:00:00',
        ),
      ),
      FeatureDetail(
        title: '合成已开始课程',
        presentation: BykcCoursePresentation(
          id: 2,
          courseName: '合成已开始课程',
          status: BykcCourseStatus.preview,
          courseSelectStartDate: '2000-01-01 08:00:00',
          courseSelectEndDate: '2000-01-02 18:00:00',
        ),
      ),
    ]);
    expect(find.text('开始选课'), findsOneWidget);
    expect(find.text('截止选课'), findsOneWidget);
    expect(find.text('2100-01-01 08:00'), findsOneWidget);
    expect(find.text('2000-01-02 18:00'), findsOneWidget);
    expect(find.textContaining('2100-01-02'), findsNothing);
    expect(find.textContaining('2000-01-01'), findsNothing);
  });
  testWidgets('已选博雅沿旧版连续滚动，不插入每20条的本地分页', (tester) async {
    await _open(tester, [
      for (var i = 1; i <= 25; i++)
        FeatureDetail(
          title: '合成已选课 $i',
          presentation: BykcChosenPresentation(
            recordId: 9000 + i,
            courseId: i,
            courseName: '合成已选课 $i',
          ),
        ),
    ], view: FeatureQueryView.bykcChosenCourses);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '详情分页',
      ),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(Card, '合成已选课 25'),
      250,
      scrollable: find.byType(Scrollable).hitTestable().last,
      maxScrolls: 40,
    );
    expect(find.widgetWithText(Card, '合成已选课 25'), findsOneWidget);
  });
  testWidgets('博雅旧版状态筛选只在面板中出现，关闭重开保留且不误发请求', (tester) async {
    final queries = <FeatureQuery>[];
    await _open(tester, const [
      FeatureDetail(
        title: '合成可选课',
        presentation: BykcCoursePresentation(
          id: 1,
          courseName: '合成可选课',
          status: BykcCourseStatus.available,
        ),
      ),
      FeatureDetail(
        title: '合成过期课',
        presentation: BykcCoursePresentation(
          id: 2,
          courseName: '合成过期课',
          status: BykcCourseStatus.expired,
        ),
      ),
    ], queries: queries);
    expect(find.text('合成过期课'), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    await openQueryPanel(tester);
    await tester.tap(find.widgetWithText(FilterChip, '已过期'));
    await closeQueryPanel(tester);
    expect(find.text('合成过期课'), findsOneWidget);
    await openQueryPanel(tester);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '已过期'))
          .selected,
      isTrue,
    );
    expect(queries, isEmpty);
  });
  testWidgets('博雅课程选择器优先使用公开typed课程ID', (tester) async {
    await _open(tester, const [
      FeatureDetail(
        title: '假标题',
        fields: [FeatureField(label: '课程 ID', value: '999')],
        presentation: BykcCoursePresentation(
          id: 7,
          courseName: '合成课',
          status: BykcCourseStatus.available,
        ),
      ),
    ]);
    await openQueryPanel(tester);
    await tester.tap(find.byType(DropdownButton<FeatureQueryView>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程详情').last);
    await tester.pumpAndSettle();
    final picker = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(picker.items!.map((item) => item.value), ['7']);
  });
  testWidgets('博雅列表沿旧版整卡进入详情，正文不堆写入按钮和编号', (tester) async {
    final queries = <FeatureQuery>[];
    await _open(tester, const [
      FeatureDetail(
        title: '兼容假标题',
        presentation: BykcCoursePresentation(
          id: 7,
          courseName: '合成博雅课',
          status: BykcCourseStatus.available,
          courseTeacher: '合成教师',
          coursePosition: '合成教室',
          courseStartDate: '2026-09-09 08:00:00',
          courseEndDate: '2026-09-09 10:00:00',
          courseCurrentCount: 1,
          courseMaxCount: 3,
        ),
        fields: [FeatureField(label: '课程 ID', value: '999')],
        actions: [
          BykcSelectAction(courseId: 7, eligibility: ActionEligibility.allowed),
        ],
        readNavigation: FeatureReadNavigation(
          feature: FeatureId.bykc,
          query: FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '7'),
        ),
      ),
    ], queries: queries);
    expect(find.text('合成博雅课'), findsOneWidget);
    expect(find.text('合成教室'), findsOneWidget);
    expect(find.textContaining('08:00'), findsOneWidget);
    expect(find.text('准备选课'), findsNothing);
    expect(find.text('999'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.widgetWithText(Card, '合成博雅课'));
    await tester.pump();
    expect(queries.single.courseId, '7');
    expect(queries.single.view, FeatureQueryView.bykcDetail);
  });
  testWidgets('博雅总体净有效次数为零仍显示，分类达标不由前端重算', (tester) async {
    await _open(tester, const [
      FeatureDetail(
        title: '总体净有效次数',
        presentation: BykcStatisticsPresentation(totalValidCount: 0),
      ),
      FeatureDetail(
        title: '分类',
        presentation: BykcCategoryPresentation(
          categoryName: '博雅课程',
          subCategoryName: '美育',
          requiredCount: 1,
          passedCount: 9,
          qualified: false,
        ),
      ),
    ], view: FeatureQueryView.bykcStatistics);
    expect(find.text('总体净有效次数'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('课程小类'), findsOneWidget);
    expect(find.text('9 / 1'), findsOneWidget);
    expect(find.text('未达标'), findsOneWidget);
    expect(find.text('达标'), findsNothing);
  });
  testWidgets('博雅已选课程卡显示考勤考核，低频配置进入详情', (tester) async {
    await _open(tester, const [
      FeatureDetail(
        title: '合成已选课',
        presentation: BykcChosenPresentation(
          recordId: 9001,
          courseId: 7,
          courseName: '合成已选课',
          checkin: 5,
          pass: null,
          score: 0,
          signPointCount: 1,
          courseSignType: 3,
        ),
        fields: [FeatureField(label: '课程 ID', value: '999')],
        actions: [
          BykcDeselectAction(
            courseId: 7,
            eligibility: ActionEligibility.allowed,
          ),
        ],
      ),
    ], view: FeatureQueryView.bykcChosenCourses);
    expect(find.text('已签到、未签退'), findsOneWidget);
    expect(find.text('待考核'), findsOneWidget);
    expect(find.text('0 分'), findsOneWidget);
    expect(find.text('准备退选'), findsNothing);
    await tester.tap(find.widgetWithText(Card, '合成已选课'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '课程详情'), findsOneWidget);
    expect(find.text('签到信息'), findsOneWidget);
    expect(find.text('准备退选'), findsOneWidget);
    expect(find.text('999'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Card, '合成已选课'), findsOneWidget);
    expect(find.text('准备退选'), findsNothing);
  });
}

Future<void> _open(
  WidgetTester tester,
  List<FeatureDetail> details, {
  FeatureQueryView view = FeatureQueryView.summary,
  List<FeatureQuery>? queries,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  var currentQuery = FeatureQuery(view: view);
  var revision = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, update) => coordinatedShell(
          initialTab: 1,
          user: const UserSummary(username: 'synthetic'),
          snapshots: {
            for (final id in FeatureId.values)
              id: FeatureSnapshot(
                feature: id,
                status: FeatureLoadStatus.success,
                details: id == FeatureId.bykc ? details : const [],
                readContext: id == FeatureId.bykc
                    ? FeatureReadContext(
                        query: currentQuery,
                        requestRevision: revision,
                      )
                    : null,
              ),
          },
          routePolicy: RoutePolicy.direct,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (_, q) async {
            queries?.add(q);
            update(() {
              currentQuery = q;
              revision++;
            });
          },
          onPrepareBykcWrite: (_, __) async => throw StateError('本用例禁止准备写入'),
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (view == FeatureQueryView.summary) {
    await openFeature(tester, FeatureId.bykc);
  } else {
    await tester.tap(find.widgetWithText(Card, FeatureId.bykc.title));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        Card,
        view == FeatureQueryView.bykcStatistics ? '课程统计' : '我的课程',
      ),
    );
    await tester.pumpAndSettle();
  }
}
