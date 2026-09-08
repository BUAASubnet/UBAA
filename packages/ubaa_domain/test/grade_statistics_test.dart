import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  GradePresentation grade(String score, double credit) =>
      GradePresentation(score: score, credit: credit);
  test('旧统计按学分加权且不使用逐门原始绩点', () {
    final value = GradeStatistics.calculate([
      const GradePresentation(score: '100', credit: 2, gradePoint: '其他原值'),
      grade('80', 3),
    ]);
    expect(value.courseCount, 2);
    expect(value.totalCredits, 5);
    expect(value.gpa, 3.55);
    expect(value.weightedAverage, 88);
    expect(value.arithmeticAverage, 90);
  });
  test('旧等级分换算且通过不通过只计课程和学分', () {
    final value = GradeStatistics.calculate([
      grade('优', 2),
      grade('良', 2),
      grade('通过', 5),
      grade('不通过', 5),
    ]);
    expect(value.courseCount, 4);
    expect(value.totalCredits, 14);
    expect(value.gpa, 3.75);
    expect(value.weightedAverage, 85);
    expect(value.arithmeticAverage, 85);
    final levels = GradeStatistics.calculate([
      for (final s in ['优秀', '良好', '中等', '及格', '不及格']) grade(s, 1),
    ]);
    expect(levels.gpa, 2.4);
    expect(levels.weightedAverage, 60);
    expect(levels.arithmeticAverage, 60);
  });
  test('没有参与项时平均值未知，未出成绩仍计正学分', () {
    final value = GradeStatistics.calculate([
      grade('通过', 2),
      grade('不通过', 2),
      const GradePresentation(credit: 3),
    ]);
    expect(value.courseCount, 3);
    expect(value.totalCredits, 7);
    expect(value.gpa, isNull);
    expect(value.weightedAverage, isNull);
    expect(value.arithmeticAverage, isNull);
  });
  test('数值60和文字及格沿旧规则保持区别，平均中点取偶', () {
    expect(GradeStatistics.calculate([grade('60', 1)]).gpa, 1);
    expect(GradeStatistics.calculate([grade('及格', 1)]).gpa, 1.7);
    expect(
      GradeStatistics.calculate([grade('80.125', 1)]).weightedAverage,
      80.12,
    );
    expect(
      GradeStatistics.calculate([grade('80.375', 1)]).arithmeticAverage,
      80.38,
    );
  });
  test('异常非有限数字不污染有效统计，原课程仍计数', () {
    final value = GradeStatistics.calculate([
      grade('80', 2),
      grade('NaN', 1),
      grade('Infinity', 1),
      grade('99', double.infinity),
      grade('100', 0),
      grade('100', -1),
    ]);
    expect(value.courseCount, 6);
    expect(value.totalCredits, 4);
    expect(value.gpa, 3.25);
    expect(value.weightedAverage, 80);
    expect(value.arithmeticAverage, 80);
    expect(GradeStatistics.calculate([]).totalCredits, 0);
  });
}
