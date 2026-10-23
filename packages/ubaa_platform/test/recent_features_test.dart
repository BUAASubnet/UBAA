import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'support/preference_fake.dart';

void main() {
  test('跨实例恢复访问顺序，账号与配置隔离，清除不影响其他账号', () async {
    final values = FakePreferences();
    PreferencesRecentFeatureStore store([String scope = 'synthetic']) =>
        PreferencesRecentFeatureStore(scope: scope, values: values);
    await store().write('a', [FeatureId.grades, FeatureId.exam]);
    await store().write('b', [FeatureId.spoc]);
    expect(await store().read('a'), [FeatureId.grades, FeatureId.exam]);
    expect(await store('other').read('a'), isEmpty);
    await store().clearAccount('a');
    expect(await store().read('a'), isEmpty);
    expect(await store().read('b'), [FeatureId.spoc]);
  });
  test('快速连续保存和清除按调用顺序执行，调用后修改输入不影响记录', () async {
    final values = FakePreferences();
    final store = PreferencesRecentFeatureStore(
      scope: 'synthetic',
      values: values,
    );
    final input = [FeatureId.grades, FeatureId.exam];
    final first = store.write('a', input);
    input.clear();
    await first;
    expect(await store.read('a'), [FeatureId.grades, FeatureId.exam]);
    final pending = [
      store.write('a', [FeatureId.spoc]),
      store.write('a', [FeatureId.judge]),
      store.clearAccount('a'),
    ];
    await Future.wait(pending);
    expect(await store.read('a'), isEmpty);
  });
  test('旧功能标识兼容移除，损坏记录可通过明确清除恢复', () async {
    final values = FakePreferences();
    final store = PreferencesRecentFeatureStore(
      scope: 'synthetic',
      values: values,
    );
    await store.write('a', [FeatureId.exam]);
    final key = values.values.keys.single;
    values.values[key] = '["exam","removed","grades","exam"]';
    expect(await store.read('a'), [FeatureId.exam, FeatureId.grades]);
    values.values[key] = '{';
    await expectLater(store.read('a'), throwsFormatException);
    await store.clearAccount('a');
    await store.write('a', [FeatureId.spoc]);
    expect(await store.read('a'), [FeatureId.spoc]);
  });
}
