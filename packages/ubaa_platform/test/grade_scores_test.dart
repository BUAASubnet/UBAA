import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  late Directory directory;
  late File file;
  late FileGradeScoreStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ubaa-grade-store-test-');
    file = File('${directory.path}/scores.json');
    store = FileGradeScoreStore(file);
  });
  tearDown(() => directory.delete(recursive: true));

  test('旧成绩基线按账号路线读取，清理只影响指定账号并保留私有权限', () async {
    await file.writeAsString(fixture());
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
      expect((await file.stat()).mode & 0x1ff, 0x180);
    }
  });

  test('损坏旧基线不覆盖，失败后串行队列仍允许后续读取', () async {
    await file.writeAsString('{损坏的合成基线');
    await expectLater(
      store.read('合成甲', ConnectionMode.direct),
      throwsFormatException,
    );
    await expectLater(store.clearAccount('合成甲'), throwsFormatException);
    var encryptedCalls = 0;
    await expectLater(
      store.migrate('合成甲', ConnectionMode.direct, (_) async {
        encryptedCalls++;
      }),
      throwsFormatException,
    );
    expect(encryptedCalls, 0);
    expect(await file.readAsString(), '{损坏的合成基线');
    await file.writeAsString(fixture());
    expect(
      (await store.read('合成甲', ConnectionMode.direct))!.scores.single.score,
      '80',
    );
  });

  test('加密确认成功才移除同账号同路线旧基线，其他范围不变', () async {
    await file.writeAsString(fixture());
    final result = await store.migrate('合成甲', ConnectionMode.direct, (
      legacy,
    ) async {
      expect(legacy!.termCode, '2026-2027-1');
      expect(legacy.scores.single.score, '80');
      expect(await file.readAsString(), fixture());
      return '已加密';
    });
    expect(result, '已加密');
    expect(await store.read('合成甲', ConnectionMode.direct), isNull);
    expect(
      (await store.read('合成甲', ConnectionMode.webvpn))!.scores.single.score,
      '90',
    );
    expect(
      (await store.read('合成乙', ConnectionMode.direct))!.scores.single.score,
      '70',
    );
    await store.clearAccount('合成甲');
    await store.clearAccount('合成乙');
    expect(await file.exists(), isFalse);
  });

  test('加密失败或退出取消保留旧文件全部原字节', () async {
    await file.writeAsString(fixture());
    for (final failure in [StateError('合成密钥不可用'), StateError('合成代次失效')]) {
      await expectLater(
        store.migrate('合成甲', ConnectionMode.direct, (_) async => throw failure),
        throwsA(same(failure)),
      );
      expect(await file.readAsString(), fixture());
    }
  });

  test('无旧文件迁移和清理不创建明文文件', () async {
    await store.migrate('合成甲', ConnectionMode.direct, (legacy) async {
      expect(legacy, isNull);
    });
    await store.clearAccount('合成甲');
    expect(await directory.list().length, 0);
  });

  test('迁移期间旧文件变化不会被旧快照覆盖或删除', () async {
    await file.writeAsString(fixture());
    await expectLater(
      store.migrate('合成甲', ConnectionMode.direct, (_) async {
        await file.writeAsString('{合成外部变化');
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), '{合成外部变化');
  });

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

String fixture() {
  Map<String, Object> entry(String score) => {
    'termCode': '2026-2027-1',
    'termName': '合成学期',
    'scores': [
      {'key': 'code:合成课程', 'courseCode': '合成课程', 'score': score},
    ],
  };
  return jsonEncode({
    'schema': 1,
    'accounts': {
      '合成甲': {'direct': entry('80'), 'webvpn': entry('90')},
      '合成乙': {'direct': entry('70')},
    },
  });
}
