import '../common/route.dart';
import 'grades.dart';

/// 本地成绩变化基线，只有已公开的课程号/课程名可作为身份后备。
final class GradeScoreEntry {
  const GradeScoreEntry({
    required this.key,
    this.courseName,
    this.courseCode,
    this.score,
  });
  final String key;
  final String? courseName, courseCode, score;
}

final class GradeScoreBaseline {
  const GradeScoreBaseline({
    required this.termCode,
    required this.termName,
    required this.scores,
  });
  final String termCode, termName;
  final List<GradeScoreEntry> scores;
  factory GradeScoreBaseline.fromRead(GradeTermRead read) {
    final overview = read.overview;
    if (overview == null) throw ArgumentError('成绩基线需要匹配学期的完整成功集合');
    String? nonBlank(String? value) =>
        value?.trim().isNotEmpty == true ? value!.trim() : null;
    final entries = <GradeScoreEntry>[];
    for (final grade in overview.grades) {
      final code = nonBlank(grade.courseCode),
          name = nonBlank(grade.courseName);
      final key = code != null
          ? 'code:$code'
          : name != null
          ? 'name:$name'
          : null;
      if (key != null)
        entries.add(
          GradeScoreEntry(
            key: key,
            courseName: name,
            courseCode: code,
            score: nonBlank(grade.score),
          ),
        );
    }
    entries.sort((a, b) => a.key.compareTo(b.key));
    return GradeScoreBaseline(
      termCode: read.code,
      termName: read.name,
      scores: List.unmodifiable(entries),
    );
  }

  GradeScoreNotice? compareWith(
    GradeScoreBaseline? previous,
    ConnectionMode route,
  ) {
    if (previous == null || previous.termCode != termCode || scores.isEmpty)
      return null;
    Map<String, List<GradeScoreEntry>> grouped(List<GradeScoreEntry> entries) {
      final result = <String, List<GradeScoreEntry>>{};
      for (final entry in entries) {
        (result[entry.key] ??= []).add(entry);
      }
      return result;
    }

    final old = grouped(previous.scores), latest = grouped(scores);
    final changes = <ChangedGradeScore>[];
    for (final entry in scores) {
      if (latest[entry.key]!.length != 1 || (old[entry.key]?.length ?? 0) > 1)
        continue;
      final before = old[entry.key]?.single;
      if (before?.score == entry.score ||
          (before == null && entry.score == null))
        continue;
      changes.add(
        ChangedGradeScore(
          courseName:
              entry.courseName ??
              before?.courseName ??
              entry.courseCode ??
              before?.courseCode ??
              '未命名课程',
          oldScore: before?.score,
          newScore: entry.score,
        ),
      );
    }
    return changes.isEmpty
        ? null
        : GradeScoreNotice(
            termCode: termCode,
            termName: termName,
            route: route,
            changes: List.unmodifiable(changes),
          );
  }
}

final class ChangedGradeScore {
  const ChangedGradeScore({
    required this.courseName,
    this.oldScore,
    this.newScore,
  });
  final String courseName;
  final String? oldScore, newScore;
}

final class GradeScoreNotice {
  const GradeScoreNotice({
    required this.termCode,
    required this.termName,
    required this.route,
    required this.changes,
  });
  final String termCode, termName;
  final ConnectionMode route;
  final List<ChangedGradeScore> changes;
}
