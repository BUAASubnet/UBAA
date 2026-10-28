import 'dart:async';
import 'package:ubaa_ui/src/features/grades/cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../assignments/content_test.dart' show showFeature;
import '../../support/navigation.dart';

void main() {
  testWidgets('本地统计渐进返回后刷新中仍显示分数', (tester) async {
    final pending = Completer<GradesAggregate>();
    void Function(GradesAggregate)? publish;
    const overview = GradesTermOverview(
      requestTerm: 'a',
      termCode: 'a',
      grades: [GradePresentation(courseName: '合成课程', score: '80', credit: 2)],
    );
    await showFeature(
      tester,
      FeatureId.grades,
      [],
      [],
      overview: overview,
      onLoadAllGrades: (force, onProgress) {
        publish = onProgress;
        return pending.future;
      },
    );
    publish!(
      GradesAggregate(
        terms: [
          GradeTermRead(
            code: 'a',
            name: '合成学期',
            result: FeatureResult.success(
              overview: overview,
              evidence: DataEvidence(
                accountId: 'synthetic',
                origin: DataOrigin.persisted,
                fetchedAt: DateTime.utc(2026, 9, 1),
                complete: true,
                savedForOffline: true,
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    final summary = tester
        .widgetList<GradeSummaryCard>(find.byType(GradeSummaryCard))
        .singleWhere((card) => card.title == '全部成绩');
    expect(summary.statistics?.courseCount, 1);
    expect(summary.notice, isNull);
    pending.complete(
      const GradesAggregate(
        terms: [
          GradeTermRead(
            code: 'a',
            name: '合成学期',
            result: FeatureResult.success(overview: overview),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
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
    await tester.enterText(searchField, 'SAFE-1');
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
  testWidgets('学期切换与行内搜索可切至历史学期并联动更新统计和列表', (tester) async {
    const term1Course = GradePresentation(
      courseName: '第一学期课程',
      courseCode: 'T1-1',
      score: '95',
      credit: 3,
      courseType: '必修',
    );
    const term2Course = GradePresentation(
      courseName: '第二学期课程',
      courseCode: 'T2-1',
      score: '88',
      credit: 2,
      courseType: '选修',
    );
    final overview1 = const GradesTermOverview(
      requestTerm: 'term1',
      termCode: 'term1',
      grades: [term1Course],
    );
    final overview2 = const GradesTermOverview(
      requestTerm: 'term2',
      termCode: 'term2',
      grades: [term2Course],
    );
    await showFeature(
      tester,
      FeatureId.grades,
      const [FeatureDetail(title: '第一学期课程', presentation: term1Course)],
      [],
      overview: overview1,
      size: const Size(1200, 1200),
      onLoadAllGrades: (_, _) async => GradesAggregate(
        terms: [
          GradeTermRead(
            code: 'term1',
            name: '2024秋',
            result: FeatureResult.success(
              overview: overview1,
              details: const [
                FeatureDetail(title: '第一学期课程', presentation: term1Course),
              ],
            ),
          ),
          GradeTermRead(
            code: 'term2',
            name: '2025春',
            result: FeatureResult.success(
              overview: overview2,
              details: const [
                FeatureDetail(title: '第二学期课程', presentation: term2Course),
              ],
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 默认在第一学期（本学期）
    expect(find.text('本学期'), findsOneWidget);
    expect(find.text('第一学期课程'), findsOneWidget);
    expect(find.text('第二学期课程'), findsNothing);

    // 点击下一学期按钮 (chevron_right)
    await tester.tap(find.byTooltip('下一学期'));
    await tester.pumpAndSettle();

    // 切换至 2025春
    expect(find.text('2025春'), findsNWidgets(2));
    expect(find.text('第二学期课程'), findsOneWidget);
    expect(find.text('第一学期课程'), findsNothing);

    // 点击上一学期回到 2024秋（本学期）
    await tester.tap(find.byTooltip('上一学期'));
    await tester.pumpAndSettle();
    expect(find.text('本学期'), findsOneWidget);
    expect(find.text('第一学期课程'), findsOneWidget);

    // 行内搜索测试
    await tester.enterText(
      find.widgetWithText(TextField, '搜索课程名称/代码/教师/属性...'),
      '不存在',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的成绩'), findsOneWidget);
    expect(find.text('第一学期课程'), findsNothing);
  });
}
