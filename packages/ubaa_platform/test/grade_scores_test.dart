import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('内存基线也精确隔离学期且空集合不覆盖', () async {
    final memory = MemoryGradeScoreStore();
    final first = value('2026-2027-1', '80'),
        second = value('2026-2027-2', '90');
    expect(await memory.update('合成甲', ConnectionMode.direct, first), isNull);
    expect(await memory.update('合成甲', ConnectionMode.direct, second), isNull);
    expect(
      (await memory.update(
        '合成甲',
        ConnectionMode.direct,
        value(first.termCode, '95'),
      ))!.scores.single.score,
      '80',
    );
    await memory.update(
      '合成甲',
      ConnectionMode.direct,
      GradeScoreBaseline(
        termCode: first.termCode,
        termName: '合成',
        scores: const [],
      ),
    );
    expect(
      (await memory.read(
        '合成甲',
        ConnectionMode.direct,
        term: first.termCode,
      ))!.scores.single.score,
      '95',
    );
    expect(
      (await memory.read(
        '合成甲',
        ConnectionMode.direct,
        term: second.termCode,
      ))!.scores.single.score,
      '90',
    );
  });
}

GradeScoreBaseline value(String term, String score) => GradeScoreBaseline(
  termCode: term,
  termName: '合成学期',
  scores: [GradeScoreEntry(key: 'code:合成课程', courseCode: '合成课程', score: score)],
);
