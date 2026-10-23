import 'package:ubaa_ui/src/features/coursework/assignment_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/navigation.dart';
import 'content_test.dart' show showFeature;

FeatureDetail spoc(
  String title,
  AssignmentSubmissionStatus status,
  String? due, {
  String? start,
}) => FeatureDetail(
  title: title,
  presentation: SpocAssignmentPresentation(
    courseId: 'c',
    courseName: 'Synthetic 课程',
    assignmentId: title,
    status: status,
    statusText: status.name,
    startTime: start,
    dueTime: due,
  ),
  readNavigation: FeatureReadNavigation(
    feature: FeatureId.spoc,
    query: FeatureQuery(view: FeatureQueryView.spocDetail, assignmentId: title),
  ),
);

void main() {
  test('SPOC 未提交条件严格匹配，未知日期和截止边界沿旧版', () {
    const defaults = AssignmentListFilters(isSpoc: true);
    final now = DateTime(2026, 10, 23, 12);
    final source = [
      spoc(
        '未提交',
        AssignmentSubmissionStatus.unsubmitted,
        '2026-10-23 12:00:00',
        start: '2026-10-21 12:00:00',
      ),
      spoc(
        '已提交',
        AssignmentSubmissionStatus.submitted,
        null,
        start: '2026-10-22 12:00:00',
      ),
      spoc(
        '部分提交',
        AssignmentSubmissionStatus.partial,
        '无法解析',
        start: '2026-10-20 12:00:00',
      ),
      spoc('未知状态', AssignmentSubmissionStatus.unknown, null),
      spoc(
        '刚截止',
        AssignmentSubmissionStatus.unsubmitted,
        '2026-10-23 11:59:59',
      ),
    ];
    List<String> titles(AssignmentListFilters filters) =>
        filters.apply(source, '', now: now).map((d) => d.title).toList();
    expect(titles(defaults), containsAll(['未提交', '已提交', '部分提交', '未知状态']));
    expect(titles(defaults), isNot(contains('刚截止')));
    final unsubmitted = defaults.copyWith(onlyUnfinished: true);
    expect(titles(unsubmitted), ['未提交']);
    final both = unsubmitted.copyWith(showExpired: true);
    expect(titles(both), ['刚截止', '未提交']);
    expect(titles(both.copyWith(showExpired: false)), ['未提交']);
    expect(titles(defaults.copyWith(byStart: true)).first, '部分提交');
    expect(
      titles(defaults.copyWith(ascending: false)),
      titles(defaults).reversed.toList(),
    );
  });

  testWidgets('SPOC 默认隐藏已截止且保留已提交，两个过滤条件独立且零读取', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(tester, FeatureId.spoc, [
      spoc(
        '当前未提交',
        AssignmentSubmissionStatus.unsubmitted,
        '2099-02-01 00:00:00',
      ),
      spoc(
        '当前已提交',
        AssignmentSubmissionStatus.submitted,
        '2099-01-01 00:00:00',
      ),
      spoc(
        '历史未提交',
        AssignmentSubmissionStatus.unsubmitted,
        '2000-01-01 00:00:00',
      ),
      spoc(
        '历史已提交',
        AssignmentSubmissionStatus.submitted,
        '2000-01-01 00:00:00',
      ),
    ], queries);
    expect(find.text('历史未提交'), findsNothing);
    expect(find.text('当前已提交'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('当前已提交')).dy,
      lessThan(tester.getTopLeft(find.text('当前未提交')).dy),
    );
    await openQueryPanel(tester);
    await tester.tap(find.text('仅显示未提交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示已截止'));
    await closeQueryPanel(tester);
    expect(find.text('历史未提交'), findsOneWidget);
    expect(find.text('历史已提交'), findsNothing);
    expect(find.text('当前已提交'), findsNothing);
    await openQueryPanel(tester);
    await tester.tap(find.text('降序'));
    await tester.enterText(
      find.widgetWithText(TextField, '课程名称或作业标题'),
      '  SYNTHETIC ',
    );
    await closeQueryPanel(tester);
    expect(find.text('当前未提交'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('当前未提交')).dy,
      lessThan(tester.getTopLeft(find.text('历史未提交')).dy),
    );
    expect(queries, isEmpty);
    await tester.tap(find.byTooltip('查看作业详情').first);
    await tester.pumpAndSettle();
    expect(queries.single.assignmentId, '当前未提交');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('历史未提交'), findsOneWidget);
    expect(find.text('历史已提交'), findsNothing);
    expect(queries, hasLength(1));
  });
}
