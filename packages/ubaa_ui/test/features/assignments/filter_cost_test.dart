import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/coursework/assignment_filters.dart';

void main() {
  test('长作业列表只提取一次筛选排序字段', () {
    var reads = 0;
    final source = List.generate(
      600,
      (index) => _CountedAssignment(index, () => reads++),
    );
    final result = const AssignmentListFilters().apply(
      source,
      '',
      now: DateTime(2026, 11, 13),
    );
    expect(result, hasLength(source.length));
    expect(
      reads,
      lessThanOrEqualTo(source.length),
      reason: '排序比较应复用已提取的字段，避免随比较次数反复解析日期',
    );
    final deadlines = result
        .map((d) => (d.presentation! as JudgeAssignmentPresentation).dueTime!)
        .toList();
    expect(deadlines, orderedEquals([...deadlines]..sort()));
  });
}

class _CountedAssignment extends FeatureDetail {
  _CountedAssignment(int index, this.onRead)
    : _presentation = JudgeAssignmentPresentation(
        courseId: 'c',
        courseName: '合成课程',
        assignmentId: '$index',
        status: AssignmentSubmissionStatus.unsubmitted,
        statusText: '未提交',
        totalProblems: 1,
        submittedCount: 0,
        dueTime:
            '2099-12-${(index * 17 % 28 + 1).toString().padLeft(2, '0')} 23:59:00',
      ),
      super(title: '合成作业 $index');

  final JudgeAssignmentPresentation _presentation;
  final void Function() onRead;

  @override
  FeaturePresentation get presentation {
    onRead();
    return _presentation;
  }
}
