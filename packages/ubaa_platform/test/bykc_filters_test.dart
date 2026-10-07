import 'dart:convert';
import 'support/preference_fake.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  late FakePreferences values;
  PreferencesBykcCourseFilterStore store() =>
      PreferencesBykcCourseFilterStore(scope: 'synthetic', values: values);
  setUp(() {
    values = FakePreferences();
  });

  test('三维选择规范化后跨新插件存储实例恢复，空状态保持不限', () async {
    final value = BykcCourseFilters(
      statuses: const [],
      categories: [' 美育 ', '美育', ''],
      campuses: [' 沙河校区 ', '沙河校区', ' ', '未指定校区'],
    );
    expect(value.isDefault, isFalse);
    await store().write('fixture-a', value);
    final restored = await store().read('fixture-a');
    expect(restored, value);
    expect(restored!.statuses, isEmpty);
    expect(restored.categories, {'美育'});
    expect(restored.campuses, {'沙河校区', '未指定校区'});
    expect(await store().read('fixture-b'), isNull);
    expect(values.values, hasLength(1));
    expect(jsonDecode(values.values.values.single), {
      'statuses': [],
      'categories': ['美育'],
      'campuses': ['未指定校区', '沙河校区'],
    });
  });

  for (final inMemory in [false, true]) {
    test('调用保存时冻结集合，随后编辑输入不改变待存内容：内存=$inMemory', () async {
      final BykcCourseFilterStore current = inMemory
          ? MemoryBykcCourseFilterStore()
          : store();
      final statuses = {BykcCourseStatus.expired};
      final categories = {'美育'};
      final campuses = {'沙河校区'};
      final value = BykcCourseFilters(
        statuses: statuses,
        categories: categories,
        campuses: campuses,
      );
      final pending = current.write('fixture-a', value);
      statuses.clear();
      categories.add('德育');
      campuses.clear();
      await pending;
      final restored = (await current.read('fixture-a'))!;
      expect(restored.statuses, {BykcCourseStatus.expired});
      expect(restored.categories, {'美育'});
      expect(restored.campuses, {'沙河校区'});
      expect(() => restored.statuses.clear(), throwsUnsupportedError);
      expect(() => restored.categories.clear(), throwsUnsupportedError);
      expect(() => restored.campuses.clear(), throwsUnsupportedError);
    });

    test('账号隔离且明确清除只删除指定账号：内存=$inMemory', () async {
      final BykcCourseFilterStore current = inMemory
          ? MemoryBykcCourseFilterStore()
          : store();
      await Future.wait([
        current.write('fixture-a', _filters('沙河校区')),
        current.write('fixture-b', _filters('学院路校区')),
      ]);
      await current.clearAccount('fixture-a');
      expect(await current.read('fixture-a'), isNull);
      expect(await current.read('fixture-b'), _filters('学院路校区'));
      await current.clearAccount('fixture-a');
      expect(await current.read('fixture-b'), _filters('学院路校区'));
    });
  }

  test('不同插件实例并发保存后清除遵循调用顺序，后续保存仍可生效', () async {
    final first = store();
    final second = store();
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

  test('缺失偏好与空三维选择不同，清除缺失账号不创建条目', () async {
    final current = store();
    await current.clearAccount('fixture-a');
    expect(values.values, isEmpty);
    expect(await current.read('fixture-a'), isNull);
    final unlimited = BykcCourseFilters(statuses: const []);
    await current.write('fixture-a', unlimited);
    expect(await store().read('fixture-a'), unlimited);
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
    test('坏数据返回固定错误且不覆盖原偏好，队列可恢复：${entry.key}', () async {
      await store().write('fixture-a', _filters('沙河校区'));
      final key = values.values.keys.single;
      final raw = entry.value is String
          ? entry.value as String
          : jsonEncode(entry.value);
      values.values[key] = raw;
      final current = store();
      final safeError = isA<BykcCourseFilterStoreException>()
          .having((e) => e.code, '错误类别', BykcCourseFilterStoreError.invalidData)
          .having((e) => e.toString(), '固定反馈', '博雅筛选偏好格式无效');
      await expectLater(current.read('fixture-a'), throwsA(safeError));
      await expectLater(
        current.write('fixture-a', _filters('杭州校区')),
        throwsA(safeError),
      );
      await expectLater(current.clearAccount('fixture-a'), throwsA(safeError));
      expect(values.values[key], raw);
      values.values.remove(key);
      await current.write('fixture-a', _filters('杭州校区'));
      expect(await current.read('fixture-a'), _filters('杭州校区'));
    });
  }

  test('插件失败只返回固定反馈，恢复后可继续保存', () async {
    final current = store();
    values.fail = true;
    await expectLater(
      current.write('fixture-a', _filters('沙河校区')),
      throwsA(
        isA<BykcCourseFilterStoreException>().having(
          (e) => e.code,
          '类别',
          BykcCourseFilterStoreError.storageFailure,
        ),
      ),
    );
    values.fail = false;
    await current.write('fixture-a', _filters('沙河校区'));
    expect(await current.read('fixture-a'), _filters('沙河校区'));
  });
}

BykcCourseFilters _filters(String campus) => BykcCourseFilters(
  statuses: const [BykcCourseStatus.expired, BykcCourseStatus.available],
  categories: const ['美育'],
  campuses: [campus],
);
