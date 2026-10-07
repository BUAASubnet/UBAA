import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'support/preference_fake.dart';

void main() {
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
    await expectLater(
      store.write('', const YgdkReminderSettings()),
      throwsArgumentError,
    );
    values.fail = true;
    await expectLater(store.read('b'), throwsStateError);
  });
}
