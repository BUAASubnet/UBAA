import '../common/route.dart';

final class HealthCloudYear {
  const HealthCloudYear(this.year, this.key);
  final int year;
  final String key;
}

enum HealthCloudGrade { missing, unknown, pass, fail }

final class HealthCloudEvent {
  const HealthCloudEvent(this.name, {this.result, this.score, this.grade});
  final String name;
  final String? result;
  final double? score;
  final String? grade;

  HealthCloudGrade get status {
    if (result == null || grade?.contains('缺项') == true) {
      return HealthCloudGrade.missing;
    }
    if (grade == '不及格') return HealthCloudGrade.fail;
    if (grade == '及格' || grade == '良好' || grade == '优秀') {
      return HealthCloudGrade.pass;
    }
    final points = score;
    return points == null
        ? HealthCloudGrade.unknown
        : points < 60
        ? HealthCloudGrade.fail
        : HealthCloudGrade.pass;
  }
}

final class HealthCloudReport {
  const HealthCloudReport({
    this.weightKg,
    this.heightCm,
    this.lungMl,
    this.reachCm,
    this.events = const [],
  });
  final double? weightKg;
  final double? heightCm;
  final double? lungMl;
  final double? reachCm;
  final List<HealthCloudEvent> events;
}

final class HealthCloudPage {
  const HealthCloudPage({
    required this.years,
    required this.selectedYear,
    required this.report,
    required this.route,
  });
  final List<HealthCloudYear> years;
  final String? selectedYear;
  final HealthCloudReport? report;
  final ConnectionMode route;
}

typedef ReadHealthCloud = Future<HealthCloudPage> Function(String? year);
