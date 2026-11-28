import 'preferences.dart';

/// 按账号隔离地点编号，白名单由 UI 组合根提供。
final class PlacePreferenceStore implements AccountPreferenceMigration {
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
  @override
  Future<bool> migrateAccount(String previous, String current) async {
    if (_store case final store?)
      return store.migrateAccount(previous, current);
    if (previous == current || !_memory.containsKey(previous)) return false;
    final value = _memory.remove(previous)!;
    if (_memory.containsKey(current)) return false;
    _memory[current] = value;
    return true;
  }

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

  Future<void> writePlace(String account, String key, String value) async {
    if (!_allowed.contains(key)) throw ArgumentError('未登记的地点偏好');
    Map<String, String> merge(Map<String, String>? current) =>
        Map.unmodifiable({...?current, key: value});
    if (_store case final store?) {
      await store.update(account, merge);
    } else {
      _memory[account] = merge(_memory[account]);
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
  static const _accentKey = 'flutter.ubaa.preferences.accent';
  static const _modes = {'system', 'light', 'dark'};
  // 平台层不认识具体预设，只校验标识形状；未知预设由界面回落默认。
  static final _accentName = RegExp(r'^[a-z]{1,32}$');
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
    return _enqueue(_key, mode);
  }

  /// 保存的主题色标识；缺失、损坏或读取失败时为 null。
  Future<String?> readAccent() async {
    try {
      final value = await _values.read(_accentKey);
      return value != null && _accentName.hasMatch(value) ? value : null;
    } on Object {
      return null;
    }
  }

  Future<void> writeAccent(String name) {
    if (!_accentName.hasMatch(name)) {
      return Future.error(ArgumentError('未知主题色'));
    }
    return _enqueue(_accentKey, name);
  }

  Future<void> _enqueue(String key, String value) {
    final next = _tail.then((_) => _values.write(key, value));
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}
