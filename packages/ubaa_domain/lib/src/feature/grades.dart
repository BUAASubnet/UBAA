import '../common/error.dart';
import '../common/route.dart';
import 'overview.dart';
import 'presentation.dart';
import 'result.dart';

/// 旧GradeScreen的本地统计；不替代公开的逐门gradePoint或学校判定。
final class GradeStatistics {
  const GradeStatistics({
    required this.courseCount,
    required this.totalCredits,
    this.gpa,
    this.weightedAverage,
    this.arithmeticAverage,
  });
  final int courseCount;
  final double? totalCredits, gpa, weightedAverage, arithmeticAverage;

  factory GradeStatistics.calculate(Iterable<GradePresentation> input) {
    final grades = input.toList();
    var totalCredits = 0.0, participatingCredits = 0.0;
    var weightedPoints = 0.0, weightedScores = 0.0, arithmeticScores = 0.0;
    var count = 0;
    for (final grade in grades) {
      final credit = grade.credit;
      if (credit == null || !credit.isFinite || credit <= 0) continue;
      totalCredits += credit;
      final score = grade.score?.trim();
      if (score == null || score.isEmpty) continue;
      final converted = _convertScore(score);
      if (converted == null) continue;
      participatingCredits += credit;
      weightedPoints += converted.$1 * credit;
      weightedScores += converted.$2 * credit;
      arithmeticScores += converted.$2;
      count++;
    }
    double? weighted(double total) =>
        participatingCredits > 0 && participatingCredits.isFinite
        ? _roundTwo(total / participatingCredits)
        : null;
    return GradeStatistics(
      courseCount: grades.length,
      totalCredits: totalCredits.isFinite ? totalCredits : null,
      gpa: weighted(weightedPoints),
      weightedAverage: weighted(weightedScores),
      arithmeticAverage: count > 0 ? _roundTwo(arithmeticScores / count) : null,
    );
  }
}

(double, double)? _convertScore(String score) {
  final level = switch (score) {
    '优' || '优秀' => (4.0, 90.0),
    '良' || '良好' => (3.5, 80.0),
    '中' || '中等' => (2.8, 70.0),
    '及格' => (1.7, 60.0),
    '不及格' => (0.0, 0.0),
    _ => null,
  };
  if (level != null) return level;
  if (score == '通过' || score == '不通过') return null;
  final numeric = double.tryParse(score);
  if (numeric == null || !numeric.isFinite) return null;
  return (
    numeric < 60 ? 0.0 : 4.0 - 3.0 * (100 - numeric) * (100 - numeric) / 1600.0,
    numeric,
  );
}

/// Kotlin round中点取偶；floorToDouble避免大数转int截断。
double? _roundTwo(double value) {
  if (!value.isFinite) return null;
  final scaled = value * 100;
  if (!scaled.isFinite) return value;
  final lower = scaled.floorToDouble();
  final fraction = scaled - lower;
  final rounded =
      lower + (fraction > .5 || (fraction == .5 && lower % 2 != 0) ? 1 : 0);
  return rounded / 100;
}

/// 一项真实学期的完整读取结果，失败与空集合分别保留。
final class GradeTermRead {
  const GradeTermRead({
    required this.code,
    required this.name,
    required this.result,
  });
  final String code, name;
  final FeatureResult result;
  GradesTermOverview? get overview {
    final value = result.overview;
    return result.error == null &&
            value is GradesTermOverview &&
            value.requestTerm == code &&
            value.termCode == code
        ? value
        : null;
  }

  ConnectionMode? get resolvedRoute => result.resolvedRoute;
}

final class GradesAggregate {
  const GradesAggregate({this.terms = const [], this.error});
  final List<GradeTermRead> terms;
  final UiError? error;
  int get loadedTerms => terms.where((t) => t.overview != null).length;
  bool get isComplete => error == null && loadedTerms == terms.length;
  GradeStatistics get statistics => GradeStatistics.calculate(
    terms.expand((t) => t.overview?.grades ?? const <GradePresentation>[]),
  );
}
