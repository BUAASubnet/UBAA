import 'preferences.dart';

/// 按账号隔离地点编号，白名单由 UI 组合根提供。
final class PlacePreferenceStore {
  PlacePreferenceStore({
    required String scope,
    required Set<String> allowedKeys,
    PreferenceValues? values,
  }) : _allowed = Set.unmodifiable(allowedKeys) {
    _store = AccountPreferences<Map<String, String>>(
      scope: scope,
      kind: 'places',
      values: values,
      decode: (value) {
        if (value is! Map<String, dynamic> ||
            value.entries.any(
              (e) => !_allowed.contains(e.key) || e.value is! String,
            ))
          throw const FormatException();
        return Map<String, String>.unmodifiable(value.cast<String, String>());
      },
      encode: (value) => value,
    );
  }
  PlacePreferenceStore.memory({required Set<String> allowedKeys})
    : _allowed = Set.unmodifiable(allowedKeys);
  final _memory = <String, Map<String, String>>{};
  final Set<String> _allowed;
  AccountPreferences<Map<String, String>>? _store;
  Future<Map<String, String>> read(String account) async {
    try {
      return _store == null
          ? (_memory[account] ?? const {})
          : await _store!.read(account) ?? const {};
    } on Object {
      return const {};
    }
  }

  Future<void> write(String account, Map<String, String> value) async {
    if (value.keys.any((key) => !_allowed.contains(key)))
      throw ArgumentError('未登记的地点偏好');
    final frozen = Map<String, String>.unmodifiable(value);
    if (_store == null) {
      _memory[account] = frozen;
    } else {
      await _store!.write(account, frozen);
    }
  }

  Future<void> clearAccount(String account) async {
    if (_store == null) {
      _memory.remove(account);
    } else {
      await _store!.clear(account);
    }
  }
}

/// 外观属于设备，不随账号退出或清除而删除。
final class ThemePreferenceStore {
  ThemePreferenceStore({PreferenceValues? values})
    : _values = values ?? PluginPreferenceValues();
  final PreferenceValues _values;
  static const _key = 'flutter.ubaa.preferences.theme';
  static const _modes = {'system', 'light', 'dark'};
  Future<void> _tail = Future.value();
  Future<String> read() async {
    try {
      final value = await _values.read(_key);
      return _modes.contains(value) ? value! : 'system';
    } on Object {
      return 'system';
    }
  }

  Future<void> write(String mode) {
    if (!_modes.contains(mode)) return Future.error(ArgumentError('未知主题'));
    final next = _tail.then((_) => _values.write(_key, mode));
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}

/// 合成宿主使用的普通偏好端口。
final class MemoryPreferenceValues implements PreferenceValues {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
