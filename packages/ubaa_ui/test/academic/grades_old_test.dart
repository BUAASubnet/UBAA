import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../coursework_content_test.dart' show showFeature;
import '../support/navigation.dart';

void main() {
  testWidgets('全部学期异步完成后同一顶栏图标更新为混合路线', (tester) async {
    final pending = Completer<GradesAggregate>();
    const overview = GradesTermOverview(
      requestTerm: 'a',
      termCode: 'a',
      grades: [],
    );
    await showFeature(
      tester,
      FeatureId.grades,
      [],
      [],
      overview: overview,
      onLoadAllGrades: (_) => pending.future,
    );
    expect(find.text('统计中'), findsNWidgets(3));
    pending.complete(
      const GradesAggregate(
        terms: [
          GradeTermRead(
            code: 'a',
            name: '甲',
            result: FeatureResult.empty(
              overview: overview,
              resolvedRoute: ConnectionMode.direct,
            ),
          ),
          GradeTermRead(
            code: 'b',
            name: '乙',
            result: FeatureResult.empty(
              overview: GradesTermOverview(
                requestTerm: 'b',
                termCode: 'b',
                grades: [],
              ),
              resolvedRoute: ConnectionMode.webvpn,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('实际路线：混合'), findsOneWidget);
    expect(find.text('统计中'), findsNothing);
  });
  testWidgets('成绩沿旧版统计和描边卡，过滤不改变完整学期统计', (tester) async {
    const scored = GradePresentation(
      courseName: '合成已出课程',
      courseCode: 'SAFE-1',
      score: '80',
      credit: 2,
      gradePoint: 'RAW-KEEP',
      courseType: '必修',
      scoreType: '正常',
    );
    const missing = GradePresentation(courseName: '合成待出课程', credit: 1);
    await showFeature(
      tester,
      FeatureId.grades,
      const [
        FeatureDetail(title: '合成已出课程', presentation: scored),
        FeatureDetail(title: '合成待出课程', presentation: missing),
      ],
      [],
      overview: const GradesTermOverview(
        requestTerm: 'term',
        termCode: 'term',
        grades: [scored, missing],
      ),
      size: const Size(1200, 1200),
    );
    expect(find.text('本学期'), findsOneWidget);
    expect(find.text('课程数'), findsOneWidget);
    expect(find.text('总学分'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('RAW-KEEP'), findsNothing);
    expect(
      tester.getTopLeft(find.text('本学期')).dy,
      lessThan(tester.getTopLeft(find.text('合成已出课程')).dy),
    );
    await openQueryPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), 'SAFE-1');
    await closeQueryPanel(tester);
    expect(find.text('合成待出课程'), findsNothing);
    final summary = find.widgetWithText(Card, '本学期');
    expect(
      find.descendant(of: summary, matching: find.text('2')),
      findsOneWidget,
    );
    await tester.tap(find.text('合成已出课程'));
    await tester.pumpAndSettle();
    expect(find.text('RAW-KEEP'), findsOneWidget);
  });
  testWidgets('真实空成绩仍展示本学期零门统计', (tester) async {
    await showFeature(
      tester,
      FeatureId.grades,
      const [],
      [],
      overview: const GradesTermOverview(
        requestTerm: 'empty',
        termCode: 'empty',
        grades: [],
      ),
    );
    expect(find.text('本学期'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('暂无成绩'), findsOneWidget);
  });
}
