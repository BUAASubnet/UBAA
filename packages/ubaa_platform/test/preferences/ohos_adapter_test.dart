import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('OHOS标准偏好接口无门面缓存，读取只请求目标键，拒绝失败回执', () async {
    final previous = SharedPreferencesStorePlatform.instance;
    final native = _NativePreferences();
    SharedPreferencesStorePlatform.instance = native;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    final first = PluginPreferenceValues(isOhos: true);
    final reopened = PluginPreferenceValues(isOhos: true);
    await first.write('fixture', 'one');
    expect(await reopened.read('fixture'), 'one');
    native.values['fixture'] = 'two';
    expect(await first.read('fixture'), 'two');
    expect(native.allowList, {'fixture'});
    native.accept = false;
    await expectLater(first.write('fixture', 'three'), throwsStateError);
    await expectLater(first.remove('fixture'), throwsStateError);
    expect(await first.read('fixture'), 'two');
    native.accept = true;
    await first.remove('fixture');
    expect(await reopened.read('fixture'), isNull);
  });
}

class _NativePreferences extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  Set<String>? allowList;
  bool accept = true;
  @override
  Future<bool> clear() async => throw StateError('禁止全库清理');
  @override
  Future<Map<String, Object>> getAll() async => throw StateError('禁止全库读取');
  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    allowList = parameters.filter.allowList;
    return {
      for (final key in allowList!)
        if (values.containsKey(key)) key: values[key]!,
    };
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    expect(valueType, 'String');
    if (accept) values[key] = value;
    return accept;
  }

  @override
  Future<bool> remove(String key) async {
    if (accept) values.remove(key);
    return accept;
  }
}
