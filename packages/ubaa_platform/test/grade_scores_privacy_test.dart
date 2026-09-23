import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('旧成绩文件不得继续写入新的明文课程或分数', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ubaa-grade-privacy-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/scores.json');
    final store = FileGradeScoreStore(file);
    await expectLater(
      store.write(
        '合成甲',
        ConnectionMode.direct,
        const GradeScoreBaseline(
          termCode: '2026-2027-1',
          termName: '合成学期',
          scores: [GradeScoreEntry(key: 'code:synthetic', score: '89')],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(await file.exists(), isFalse);
  });
}
