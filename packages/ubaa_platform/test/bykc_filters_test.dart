import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ubaa-bykc-filter-test-');
    file = File('${directory.path}/filters.json');
  });
  tearDown(() => directory.delete(recursive: true));

  test('三维选择规范化后跨新文件存储实例恢复，空状态保持不限', () async {
    final value = BykcCourseFilters(
      statuses: const [],
      categories: [' 美育 ', '美育', ''],
      campuses: [' 沙河校区 ', '沙河校区', ' ', '未指定校区'],
    );
    expect(value.isDefault, isFalse);
    await FileBykcCourseFilterStore(file).write('fixture-a', value);
    final restored = await FileBykcCourseFilterStore(file).read('fixture-a');
    expect(restored, value);
    expect(restored!.statuses, isEmpty);
    expect(restored.categories, {'美育'});
    expect(restored.campuses, {'沙河校区', '未指定校区'});
    expect(await FileBykcCourseFilterStore(file).read('fixture-b'), isNull);
    final data = jsonDecode(await file.readAsString()) as Map;
    expect(data.keys, unorderedEquals(['schema', 'accounts']));
    expect((data['accounts'] as Map)['fixture-a'], {
      'statuses': [],
      'categories': ['美育'],
      'campuses': ['未指定校区', '沙河校区'],
    });
    expect(await directory.list().length, 1);
    if (Platform.isMacOS || Platform.isLinux) {
      expect((await file.stat()).mode & 0x1ff, 0x180);
    }
  });

  for (final inMemory in [false, true]) {
    test('调用保存时冻结集合，随后编辑输入不改变待存内容：内存=$inMemory', () async {
      final BykcCourseFilterStore store = inMemory
          ? MemoryBykcCourseFilterStore()
          : FileBykcCourseFilterStore(file);
      final statuses = {BykcCourseStatus.expired};
      final categories = {'美育'};
      final campuses = {'沙河校区'};
      final value = BykcCourseFilters(
        statuses: statuses,
        categories: categories,
        campuses: campuses,
      );
      final pending = store.write('fixture-a', value);
      statuses.clear();
      categories.add('德育');
      campuses.clear();
      await pending;
      final restored = (await store.read('fixture-a'))!;
      expect(restored.statuses, {BykcCourseStatus.expired});
      expect(restored.categories, {'美育'});
      expect(restored.campuses, {'沙河校区'});
      expect(() => restored.statuses.clear(), throwsUnsupportedError);
      expect(() => restored.categories.clear(), throwsUnsupportedError);
      expect(() => restored.campuses.clear(), throwsUnsupportedError);
    });

    test('账号隔离且明确清除只删除指定账号：内存=$inMemory', () async {
      final BykcCourseFilterStore store = inMemory
          ? MemoryBykcCourseFilterStore()
          : FileBykcCourseFilterStore(file);
      await Future.wait([
        store.write('fixture-a', _filters('沙河校区')),
        store.write('fixture-b', _filters('学院路校区')),
      ]);
      await store.clearAccount('fixture-a');
      expect(await store.read('fixture-a'), isNull);
      expect(await store.read('fixture-b'), _filters('学院路校区'));
      await store.clearAccount('fixture-a');
      expect(await store.read('fixture-b'), _filters('学院路校区'));
    });
  }

  test('不同文件实例并发保存后清除遵循调用顺序，后续保存仍可生效', () async {
    final first = FileBykcCourseFilterStore(file);
    final second = FileBykcCourseFilterStore(File(file.path));
    final operations = [
      first.write('fixture-a', _filters('沙河校区')),
      second.write('fixture-b', _filters('学院路校区')),
      second.clearAccount('fixture-a'),
      first.write('fixture-b', _filters('杭州校区')),
    ];
    await Future.wait(operations);
    expect(await first.read('fixture-a'), isNull);
    expect(await second.read('fixture-b'), _filters('杭州校区'));
    await Future.wait([
      first.clearAccount('fixture-b'),
      second.write('fixture-b', _filters('未指定校区')),
    ]);
    expect(await first.read('fixture-b'), _filters('未指定校区'));
  });

  test('缺失偏好与空三维选择不同，清除缺失账号不创建文件', () async {
    final store = FileBykcCourseFilterStore(file);
    await store.clearAccount('fixture-a');
    expect(await file.exists(), isFalse);
    expect(await store.read('fixture-a'), isNull);
    final unlimited = BykcCourseFilters(statuses: const []);
    await store.write('fixture-a', unlimited);
    expect(await FileBykcCourseFilterStore(file).read('fixture-a'), unlimited);
    expect(unlimited.isDefault, isFalse);
    expect(const BykcCourseFilters.defaults().isDefault, isTrue);
  });

  final malformed = <String, Object>{
    '损坏JSON': '{fixture-private-marker',
    '缺少状态集合': {'categories': <String>[], 'campuses': <String>[]},
    '未知状态': {
      'statuses': ['fixture-private-marker'],
      'categories': <String>[],
      'campuses': <String>[],
    },
    '未知类别': {
      'statuses': <String>[],
      'categories': ['未知类型'],
      'campuses': <String>[],
    },
    '非字符串校区': {
      'statuses': <String>[],
      'categories': <String>[],
      'campuses': [1],
    },
    '越界附加字段': {
      'statuses': <String>[],
      'categories': <String>[],
      'campuses': <String>[],
      'raw': 'fixture-private-marker',
    },
  };
  for (final entry in malformed.entries) {
    test('坏数据返回固定错误且不覆盖原文件，队列可恢复：${entry.key}', () async {
      final raw = entry.value is String
          ? entry.value as String
          : jsonEncode({
              'schema': 1,
              'accounts': {'fixture-a': entry.value},
            });
      await file.writeAsString(raw);
      final store = FileBykcCourseFilterStore(file);
      final safeError = isA<BykcCourseFilterStoreException>()
          .having((e) => e.code, '错误类别', BykcCourseFilterStoreError.invalidData)
          .having((e) => e.toString(), '固定反馈', '博雅筛选偏好格式无效');
      await expectLater(store.read('fixture-a'), throwsA(safeError));
      await expectLater(
        store.write('fixture-a', _filters('杭州校区')),
        throwsA(safeError),
      );
      await expectLater(store.clearAccount('fixture-a'), throwsA(safeError));
      expect(await file.readAsString(), raw);
      await file.writeAsString('{"schema":1,"accounts":{}}');
      await store.write('fixture-a', _filters('杭州校区'));
      expect(await store.read('fixture-a'), _filters('杭州校区'));
    });
  }

  test('文件失败只返回固定反馈且后续操作可恢复', () async {
    final blocker = File('${directory.path}/blocked');
    await blocker.writeAsString('合成障碍文件');
    final store = FileBykcCourseFilterStore(
      File('${blocker.path}/filters.json'),
    );
    await expectLater(
      store.write('fixture-private-account', _filters('沙河校区')),
      throwsA(
        isA<BykcCourseFilterStoreException>()
            .having(
              (e) => e.code,
              '错误类别',
              BykcCourseFilterStoreError.storageFailure,
            )
            .having((e) => e.toString(), '固定反馈', '博雅筛选偏好存储失败'),
      ),
    );
    await blocker.delete();
    await store.write('fixture-a', _filters('沙河校区'));
    expect(await store.read('fixture-a'), _filters('沙河校区'));
  });
}

BykcCourseFilters _filters(String campus) => BykcCourseFilters(
  statuses: const [BykcCourseStatus.expired, BykcCourseStatus.available],
  categories: const ['美育'],
  campuses: [campus],
);
