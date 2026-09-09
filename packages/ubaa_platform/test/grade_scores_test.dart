import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('成绩本地基线按账号和实际路线隔离，清理只影响指定账号', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ubaa-grade-store-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileGradeScoreStore(File('${directory.path}/scores.json'));
    await Future.wait([
      store.write('合成甲', ConnectionMode.direct, value('80')),
      store.write('合成甲', ConnectionMode.webvpn, value('90')),
      store.write('合成乙', ConnectionMode.direct, value('70')),
    ]);
    expect(
      (await store.read('合成甲', ConnectionMode.direct))!.scores.single.score,
      '80',
    );
    expect(
      (await store.read('合成甲', ConnectionMode.webvpn))!.scores.single.score,
      '90',
    );
    await store.clearAccount('合成甲');
    expect(await store.read('合成甲', ConnectionMode.direct), isNull);
    expect(await store.read('合成甲', ConnectionMode.webvpn), isNull);
    expect(
      (await store.read('合成乙', ConnectionMode.direct))!.scores.single.score,
      '70',
    );
    expect(await directory.list().length, 1);
    if (Platform.isMacOS || Platform.isLinux) {
      expect((await store.file.stat()).mode & 0x1ff, 0x180);
    }
  });
  test('损坏成绩基线不覆盖，读取失败后串行队列仍允许后续读取', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ubaa-grade-store-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/scores.json');
    await file.writeAsString('{损坏的合成基线');
    final store = FileGradeScoreStore(file);
    await expectLater(
      store.read('合成甲', ConnectionMode.direct),
      throwsFormatException,
    );
    await expectLater(
      store.write('合成甲', ConnectionMode.direct, value('80')),
      throwsFormatException,
    );
    expect(await file.readAsString(), '{损坏的合成基线');
    await file.writeAsString('{"schema":1,"accounts":{}}');
    await store.write('合成甲', ConnectionMode.direct, value('90'));
    expect(
      (await store.read('合成甲', ConnectionMode.direct))!.scores.single.score,
      '90',
    );
  });
}

GradeScoreBaseline value(String score) => GradeScoreBaseline(
  termCode: 'term',
  termName: '合成学期',
  scores: [GradeScoreEntry(key: 'code:合成课程', courseCode: '合成课程', score: score)],
);
