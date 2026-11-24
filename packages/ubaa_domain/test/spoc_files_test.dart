import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('旧详情缺少附件与约束时仍可展示', () {
    const item = SpocAssignmentPresentation(
      courseId: 'course',
      courseName: '合成课程',
      assignmentId: 'assignment',
      status: AssignmentSubmissionStatus.unknown,
      statusText: '未知',
      isDetail: true,
    );
    expect(item.attachment, isNull);
    expect(item.submittedFile, isNull);
    expect(item.submitModes, isEmpty);
    expect(item.allowedExtensions, isEmpty);
    expect(item.isGroupAssignment, isFalse);
    expect(item.maxSubmissions, isNull);
    expect(item.submissionCount, isNull);
    expect(item.lateSubmissionDeadline, isNull);
  });
}
