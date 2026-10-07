import 'package:ubaa_platform/ubaa_platform.dart';

class FakePreferences implements PreferenceValues {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('合成失败');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('合成失败');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (fail) throw StateError('合成失败');
    values.remove(key);
  }
}
