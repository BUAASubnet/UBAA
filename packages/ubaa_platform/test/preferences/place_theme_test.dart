import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../support/preference_fake.dart';

void main() {
  test('地点跨实例恢复、账号隔离、白名单拒绝和清除', () async {
    final values = FakePreferences();
    PlacePreferenceStore store() => PlacePreferenceStore(
      scope: '测试',
      allowedKeys: {'campus'},
      values: values,
    );
    await store().write('甲', {'campus': '沙河'});
    await store().write('乙', {'campus': '学院路'});
    expect(await store().read('甲'), {'campus': '沙河'});
    await expectLater(store().write('甲', {'未知': '值'}), throwsArgumentError);
    await store().clearAccount('甲');
    expect(await store().read('甲'), isEmpty);
    expect(await store().read('乙'), {'campus': '学院路'});
    for (final raw in ['{损坏', '{"未知":"值"}', '{"campus":42}']) {
      values.values.updateAll((_, _) => raw);
      expect(await store().read('乙'), isEmpty);
    }
    await store().clearAccount('乙');
    expect(values.values, isEmpty);
  });
  test('设备主题跨实例恢复，损坏或失败回落系统主题', () async {
    final values = FakePreferences();
    final store = ThemePreferenceStore(values: values);
    expect(await store.read(), 'system');
    await store.write('dark');
    expect(await ThemePreferenceStore(values: values).read(), 'dark');
    await expectLater(store.write('未知'), throwsArgumentError);
    values.values.updateAll((_, _) => '损坏');
    expect(await store.read(), 'system');
    values.fail = true;
    expect(await store.read(), 'system');
  });
}
