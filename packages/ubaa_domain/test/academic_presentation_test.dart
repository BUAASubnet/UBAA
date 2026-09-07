import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('展示与读导航为可选扩展且不改变原有typed写动作', () {
    const action = SigninPerformAction(
      scheduleId: 'fixture-id',
      eligibility: ActionEligibility.allowed,
    );
    const detail = FeatureDetail(title: '兼容旧调用', actions: [action]);
    expect(detail.presentation, isNull);
    expect(detail.readNavigation, isNull);
    expect(detail.action<SigninPerformAction>(), same(action));
  });

  test('学业公开展示模型保留null字符串及精确不可变节次令牌', () {
    const course = ScheduleCoursePresentation(
      courseCode: 'course',
      endTime: '结束待定',
    );
    expect(course.dayOfWeek, isNull);
    expect(course.endTime, '结束待定');
    const grade = GradePresentation(score: '通过', gradePoint: '优秀');
    expect(grade.credit, isNull);
    expect(grade.gradePoint, '优秀');
    const room = ClassroomPresentation(
      roomId: 'R',
      floorId: 'F',
      floorName: '三层',
      availableSections: '3, 13,, x',
    );
    expect(room.sectionTokens, ['3', '13', 'x']);
    expect(() => room.sectionTokens.clear(), throwsUnsupportedError);
  });

  test('读导航保留typed学期周次而不使用展示标题作为参数', () {
    const detail = FeatureDetail(
      title: '这不是学期编码',
      readNavigation: FeatureReadNavigation(
        feature: FeatureId.schedule,
        query: FeatureQuery(
          view: FeatureQueryView.scheduleWeek,
          term: '2026-2027-1',
          week: 4,
        ),
      ),
    );
    expect(detail.readNavigation!.query.term, '2026-2027-1');
    expect(detail.readNavigation!.query.week, 4);
    expect(detail.actions, isEmpty);
  });
}
