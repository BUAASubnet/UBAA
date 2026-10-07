import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// 仅普通 UI 偏好；密码、会话与业务内容不进入此端口。
abstract interface class PreferenceValues {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

final class PluginPreferenceValues implements PreferenceValues {
  PluginPreferenceValues({bool? isOhos})
    : _isOhos = isOhos ?? Platform.operatingSystem == 'ohos';
  final bool _isOhos;
  SharedPreferencesAsync? _async;
  SharedPreferencesAsync get _store => _async ??= SharedPreferencesAsync();
  // OHOS 社区插件实现标准 StorePlatform；直接调用避免旧门面的单例缓存。
  @override
  Future<String?> read(String key) async {
    if (!_isOhos) return _store.getString(key);
    final values = await SharedPreferencesStorePlatform.instance
        .getAllWithParameters(
          GetAllParameters(
            filter: PreferencesFilter(prefix: '', allowList: {key}),
          ),
        );
    return values[key] as String?;
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_isOhos) return _store.setString(key, value);
    if (!await SharedPreferencesStorePlatform.instance.setValue(
      'String',
      key,
      value,
    )) {
      throw StateError('偏好保存失败');
    }
  }

  @override
  Future<void> remove(String key) async {
    if (!_isOhos) return _store.remove(key);
    if (!await SharedPreferencesStorePlatform.instance.remove(key)) {
      throw StateError('偏好清除失败');
    }
  }
}

/// 账号独立键，不进行整表读改写；同一 isolate 的全部偏好实例共享顺序，兼容桌面插件的文件后端。
final class AccountPreferences<T> {
  AccountPreferences({
    required this.scope,
    required this.kind,
    required this.decode,
    required this.encode,
    PreferenceValues? values,
  }) : values = values ?? PluginPreferenceValues();
  final String scope, kind;
  final T Function(Object?) decode;
  final Object Function(T) encode;
  final PreferenceValues values;
  static Future<void> _tail = Future<void>.value();
  String _key(String account) {
    if (account.trim().isEmpty) throw ArgumentError('偏好账号不能为空');
    final digest = sha256.convert(utf8.encode(jsonEncode([scope, account])));
    return 'flutter.ubaa.preferences.v2.$kind.$digest';
  }

  Future<R> _serial<R>(
    String account,
    Future<R> Function(String) action,
  ) async {
    final key = _key(account);
    final next = _tail.then((_) => action(key));
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<T?> _read(String key) async {
    final raw = await values.read(key);
    return raw == null ? null : decode(jsonDecode(raw));
  }

  Future<T?> read(String account) => _serial(account, _read);
  Future<void> write(String account, T value) => _serial(account, (key) async {
    await _read(key); // 损坏偏好不被普通保存静默覆盖。
    await values.write(key, jsonEncode(encode(value)));
  });
  Future<void> clear(String account) => _serial(account, (key) async {
    // 明确删除只依赖账号键；损坏的普通偏好也必须能够恢复。
    // 保留普通保存的严格解码，插件删除错误仍交由调用方处理。
    await values.remove(key);
  });
}
