import 'package:ubaa_ui/src/features/coursework/judge_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/navigation.dart';
import 'content_test.dart' show showFeature;

FeatureDetail assignment(
  String title,
  AssignmentSubmissionStatus status,
  String? due,
) => FeatureDetail(
  title: title,
  presentation: JudgeAssignmentPresentation(
    courseId: 'c',
    courseName: '合成课程',
    assignmentId: title,
    status: status,
    statusText: status.name,
    totalProblems: 2,
    submittedCount: 0,
    startTime: title == '稍后' ? '2098-01-01T00:00:00' : '2098-02-01T00:00:00',
    dueTime: due,
  ),
);

void main() {
  test('旧版日期边界、未知日期、状态互斥和排序方向', () {
    final now = DateTime(2026, 10, 23, 12);
    final source = [
      assignment(
        '截止相等',
        AssignmentSubmissionStatus.partial,
        '2026-10-23 12:00:00',
      ),
      assignment(
        '刚截止',
        AssignmentSubmissionStatus.unsubmitted,
        '2026-10-23 11:59:59',
      ),
      assignment(
        '未知日期',
        AssignmentSubmissionStatus.unsubmitted,
        '2026-02-30 00:00:00',
      ),
      assignment(
        '较早',
        AssignmentSubmissionStatus.unsubmitted,
        '2099-01-01 00:00:00',
      ),
      assignment(
        '稍后',
        AssignmentSubmissionStatus.partial,
        '2099-02-01 00:00:00',
      ),
      assignment('已完成', AssignmentSubmissionStatus.submitted, null),
      assignment('未知状态', AssignmentSubmissionStatus.unknown, null),
    ];
    List<String> titles(JudgeListFilters filters, {String search = ''}) =>
        filters.apply(source, search, now: now).map((d) => d.title).toList();
    const defaults = JudgeListFilters();
    expect(titles(defaults), ['截止相等', '较早', '稍后', '未知日期']);
    expect(titles(defaults.copyWith(ascending: false)), [
      '未知日期',
      '稍后',
      '较早',
      '截止相等',
    ]);
    expect(titles(defaults.copyWith(byStart: true)).first, '稍后');
    expect(titles(defaults, search: ' 合成课程 '), titles(defaults));
    expect(titles(defaults, search: 'unsubmitted'), isEmpty);
    final expired = defaults.copyWith(showExpired: true);
    expect(expired.onlyUnfinished, isFalse);
    expect(titles(expired), containsAll(['刚截止', '已完成', '未知状态']));
    expect(expired.copyWith(onlyUnfinished: true).onlyUnfinished, isFalse);
    expect(expired.copyWith(showExpired: false).onlyUnfinished, isFalse);
  });

  testWidgets('历史范围通过独立按钮读取一次，随后切换条件仅过滤已有数据', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(tester, FeatureId.judge, [
      assignment('当前', AssignmentSubmissionStatus.unsubmitted, null),
    ], queries);
    await openQueryPanel(tester);
    await tester.tap(find.text('显示已截止'));
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
    await tester.ensureVisible(find.text('加载历史作业'));
    await tester.tap(find.text('加载历史作业'));
    await tester.pumpAndSettle();
    expect(queries.single.view, FeatureQueryView.summary);
    expect(queries.single.includeExpired, isTrue);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('显示已截止'));
      await tester.pumpAndSettle();
    }
    expect(queries, hasLength(1));
  });

  testWidgets('默认只展示未截止未完成，筛选排序搜索不发起读取', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(
      tester,
      FeatureId.judge,
      [
        assignment(
          '稍后',
          AssignmentSubmissionStatus.partial,
          '2099-02-01T00:00:00',
        ),
        assignment(
          '较早',
          AssignmentSubmissionStatus.unsubmitted,
          '2099-01-01T00:00:00',
        ),
        assignment(
          '已完成',
          AssignmentSubmissionStatus.submitted,
          '2099-01-01T00:00:00',
        ),
        assignment(
          '历史',
          AssignmentSubmissionStatus.unsubmitted,
          '2000-01-01T00:00:00',
        ),
        assignment('未知', AssignmentSubmissionStatus.unknown, null),
      ],
      queries,
      query: const FeatureQuery(includeExpired: true),
    );
    expect(find.text('已完成'), findsNothing);
    expect(find.text('历史'), findsNothing);
    expect(find.text('未知'), findsNothing);
    expect(
      tester.getTopLeft(find.text('较早')).dy,
      lessThan(tester.getTopLeft(find.text('稍后')).dy),
    );
    await openQueryPanel(tester);
    await tester.tap(find.text('显示已截止'));
    await tester.pumpAndSettle();
    await closeQueryPanel(tester);
    expect(find.text('历史'), findsOneWidget);
    await openQueryPanel(tester);
    await tester.tap(find.text('降序'));
    await tester.enterText(find.widgetWithText(TextField, '课程名称或作业标题'), '稍后');
    await closeQueryPanel(tester);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('较早'), findsNothing);
    expect(queries, isEmpty);
  });
}
