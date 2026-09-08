import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('考试结束沿旧版严格大于结束时间，不根据状态或开始时间猜测', () {
    const exam = ExamPresentation(
      arranged: true,
      date: '2026-09-09 00:00:00',
      startTime: '08:00',
      endTime: '09:40',
      status: 99,
    );
    expect(exam.isFinishedAt(DateTime(2026, 9, 9, 9, 40)), isFalse);
    expect(exam.isFinishedAt(DateTime(2026, 9, 9, 9, 40, 0, 0, 1)), isTrue);
    expect(exam.isFinishedAt(DateTime(2026, 9, 8, 23, 59)), isFalse);
    expect(exam.isFinishedAt(DateTime(2026, 9, 10)), isTrue);
    const other = ExamPresentation(arranged: false, date: '2020-01-01');
    expect(other.isFinishedAt(DateTime(2026)), isFalse);
  });
  test('缺失和异常结束时间按旧23:59，非法日期不归一化而误隐藏', () {
    for (final end in <String?>[null, '待定', '24:00', '09:61']) {
      final exam = ExamPresentation(
        arranged: true,
        date: '2026-09-09',
        endTime: end,
      );
      expect(exam.isFinishedAt(DateTime(2026, 9, 9, 23, 59)), isFalse);
      expect(exam.isFinishedAt(DateTime(2026, 9, 9, 23, 59, 1)), isTrue);
    }
    for (final date in <String?>[
      null,
      '教务待确认',
      '2026-02-30',
      '2026-13-01',
      '2026-09-09T08:00:00',
    ]) {
      final exam = ExamPresentation(arranged: true, date: date);
      expect(exam.calendarDate, isNull);
      expect(exam.isFinishedAt(DateTime(2999)), isFalse);
    }
    const precise = ExamPresentation(
      arranged: true,
      date: '2026-09-09',
      endTime: '09:40:30.123456',
    );
    expect(
      precise.isFinishedAt(DateTime(2026, 9, 9, 9, 40, 30, 123, 456)),
      isFalse,
    );
    expect(
      precise.isFinishedAt(DateTime(2026, 9, 9, 9, 40, 30, 123, 457)),
      isTrue,
    );
  });
}
