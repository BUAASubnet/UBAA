import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'support/preference_fake.dart';

void main() {
  test('旧版关闭选择保留，旧版开启值使用新默认范围', () async {
    final values = FakePreferences();
    final store = PreferencesYgdkReminderStore(scope: 'legacy', values: values);
    await store.write('account', const YgdkReminderSettings());
    final key = values.values.keys.single;
    for (final enabled in [true, false]) {
      values.values[key] = jsonEncode({
        'enabled': enabled,
        'weekDoneKey': 'term:11',
        'termDoneKey': null,
      });
      final saved = await store.read('account');
      expect(saved.manualEnabled, enabled ? isNull : isFalse);
      expect(saved.weekDoneKey, 'term:11');
    }
  });

  test('手动提醒选择按账号持久保存，自动进度不变成手动选择', () async {
    final values = FakePreferences();
    PreferencesYgdkReminderStore store() =>
        PreferencesYgdkReminderStore(scope: 'manual', values: values);
    for (final enabled in [true, false]) {
      await store().write(
        'account',
        YgdkReminderSettings(
          enabled: enabled,
          manualEnabled: enabled,
          weekDoneKey: 'term:11',
        ),
      );
      final saved = await store().read('account');
      expect(saved.manualEnabled, enabled);
      expect(saved.weekDoneKey, 'term:11');
    }
    await store().write(
      'automatic',
      const YgdkReminderSettings(weekDoneKey: 'term:12'),
    );
    expect((await store().read('automatic')).manualEnabled, isNull);
  });

  test('提醒默认开启，重开实例保留账号周次学期隔离', () async {
    final values = FakePreferences();
    PreferencesYgdkReminderStore store([String scope = 'a']) =>
        PreferencesYgdkReminderStore(scope: scope, values: values);
    expect((await store().read('synthetic-a')).enabled, isTrue);
    await Future.wait([
      store().write(
        'synthetic-a',
        const YgdkReminderSettings(
          enabled: false,
          weekDoneKey: 'term:11',
          termDoneKey: 'term',
        ),
      ),
      store().write(
        'synthetic-b',
        const YgdkReminderSettings(weekDoneKey: 'term:12'),
      ),
    ]);
    expect((await store().read('synthetic-a')).enabled, isFalse);
    expect((await store().read('synthetic-b')).weekDoneKey, 'term:12');
    expect((await store('b').read('synthetic-a')).enabled, isTrue);
    await store().clear('synthetic-a');
    expect((await store().read('synthetic-a')).weekDoneKey, isNull);
    expect((await store().read('synthetic-b')).weekDoneKey, 'term:12');
  });
  test('损坏值拒绝覆盖，插件错误传播，空账号不能写入', () async {
    final values = FakePreferences();
    final store = PreferencesYgdkReminderStore(scope: 'a', values: values);
    await store.write('a', const YgdkReminderSettings());
    final key = values.values.keys.single;
    values.values[key] = '{无效';
    await expectLater(store.read('a'), throwsFormatException);
    await expectLater(
      store.write('a', const YgdkReminderSettings()),
      throwsFormatException,
    );
    expect(values.values[key], '{无效');
    await store.write('b', const YgdkReminderSettings(enabled: false));
    await store.clear('a');
    expect(values.values.containsKey(key), isFalse);
    expect((await store.read('a')).enabled, isTrue);
    expect((await store.read('b')).enabled, isFalse);
    await expectLater(
      store.write('', const YgdkReminderSettings()),
      throwsArgumentError,
    );
    values.fail = true;
    await expectLater(store.read('b'), throwsStateError);
    await expectLater(store.clear('b'), throwsStateError);
  });
}
