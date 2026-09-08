import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../coursework_content_test.dart' show showFeature;
import '../support/navigation.dart';

void main() {
  testWidgets('考试跨本地20条分组，结束默认收起且未来先于待定', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(tester, FeatureId.exam, [
      for (var i = 0; i < 24; i++)
        FeatureDetail(
          title: '已结束$i',
          presentation: const ExamPresentation(
            arranged: true,
            date: '2020-01-01',
          ),
        ),
      const FeatureDetail(
        title: '日期异常',
        presentation: ExamPresentation(arranged: true, date: '教务待确认'),
      ),
      const FeatureDetail(
        title: '较晚考试',
        presentation: ExamPresentation(arranged: true, date: '2999-10-02'),
      ),
      const FeatureDetail(
        title: '较早考试',
        presentation: ExamPresentation(
          arranged: true,
          date: '2999-10-01',
          seat: 'A018',
          startTime: '09:00',
        ),
      ),
    ], queries);
    expect(find.text('已结束考试 (24)'), findsOneWidget);
    expect(find.text('已结束0'), findsNothing);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('座位 A018'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('较早考试')).dy,
      lessThan(tester.getTopLeft(find.text('较晚考试')).dy),
    );
    expect(
      tester.getTopLeft(find.text('较晚考试')).dy,
      lessThan(tester.getTopLeft(find.text('日期异常')).dy),
    );
    await tester.tap(find.text('已结束考试 (24)'));
    await tester.pumpAndSettle();
    expect(find.text('已结束0'), findsOneWidget);
    await openQueryPanel(tester);
    await closeQueryPanel(tester);
    expect(find.text('已结束0'), findsOneWidget);
    expect(queries, isEmpty);
  });
  testWidgets('考试列表低频字段不占正文，本地详情保留完整日期和原字段', (tester) async {
    await showFeature(tester, FeatureId.exam, const [
      FeatureDetail(
        title: '合成考试',
        fields: [FeatureField(label: '原字段', value: '保留值')],
        presentation: ExamPresentation(
          arranged: true,
          date: '2999-10-01',
          startTime: '09:00',
          taskId: 'TASK-KEEP',
          type: '闭卷',
        ),
      ),
      FeatureDetail(
        title: '未安排课程',
        presentation: ExamPresentation(arranged: false),
      ),
    ], []);
    expect(find.text('未安排/其他'), findsOneWidget);
    expect(find.text('TASK-KEEP'), findsNothing);
    expect(find.text('更多信息'), findsNothing);
    await tester.tap(find.text('合成考试'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('2999-10-01'), findsOneWidget);
    await tester.tap(find.text('更多信息'));
    await tester.pumpAndSettle();
    expect(find.text('TASK-KEEP'), findsOneWidget);
    expect(find.text('保留值'), findsOneWidget);
  });
  testWidgets('考试低频typed任务编号也可从顶栏筛选，收起后不丢条件', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(tester, FeatureId.exam, const [
      FeatureDetail(
        title: '目标考试',
        presentation: ExamPresentation(
          arranged: true,
          taskId: 'TASK-ONLY',
          date: '2999-01-01',
        ),
      ),
      FeatureDetail(
        title: '其他考试',
        presentation: ExamPresentation(arranged: true, date: '2999-01-01'),
      ),
    ], queries);
    await openQueryPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), 'TASK-ONLY');
    await closeQueryPanel(tester);
    expect(find.text('目标考试'), findsOneWidget);
    expect(find.text('其他考试'), findsNothing);
    expect(queries, isEmpty);
  });

  testWidgets('签到已完成使用右侧状态图标，低频字段按需查看', (tester) async {
    await showFeature(tester, FeatureId.signin, const [
      FeatureDetail(
        title: '合成已签到课程',
        fields: [FeatureField(label: '原字段', value: '只在详情')],
        presentation: SigninPresentation(
          courseId: 'course',
          classBeginTime: '08:00',
          classEndTime: '09:40',
          signStatus: 1,
        ),
        actions: [
          SigninPerformAction(
            scheduleId: 'target',
            eligibility: ActionEligibility.denied,
          ),
        ],
      ),
    ], []);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(find.text('更多信息'), findsNothing);
    final title = tester.getRect(find.text('合成已签到课程'));
    final icon = tester.getRect(find.byIcon(Icons.check_circle));
    expect(icon.left, greaterThan(title.left));
    expect((icon.center.dy - title.center.dy).abs(), lessThan(60));
    await tester.tap(find.byTooltip('课程详情'));
    await tester.pumpAndSettle();
    expect(find.text('只在详情'), findsOneWidget);
    expect(find.textContaining('不能重复提交'), findsOneWidget);
  });
}
