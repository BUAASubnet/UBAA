import 'infrastructure/preferences.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
export 'package:ubaa_domain/ubaa_domain.dart' show YgdkReminderSettings;

abstract interface class YgdkReminderStore {
  Future<YgdkReminderSettings> read(String accountKey);
  Future<void> write(String accountKey, YgdkReminderSettings settings);
  Future<void> clear(String accountKey);
}

final class MemoryYgdkReminderStore implements YgdkReminderStore {
  final _values = <String, YgdkReminderSettings>{};
  @override
  Future<YgdkReminderSettings> read(String key) async =>
      _values[key] ?? const YgdkReminderSettings();
  @override
  Future<void> write(String key, YgdkReminderSettings value) async {
    _values[key] = value;
  }

  @override
  Future<void> clear(String key) async {
    _values.remove(key);
  }
}

/// 只持久保存提醒偏好，不承担系统通知调度。
final class PreferencesYgdkReminderStore implements YgdkReminderStore {
  PreferencesYgdkReminderStore({
    required String scope,
    PreferenceValues? values,
  }) : _store = AccountPreferences(
         scope: scope,
         kind: 'reminders',
         values: values,
         decode: _decode,
         encode: (value) => {
           'enabled': value.enabled,
           'weekDoneKey': value.weekDoneKey,
           'termDoneKey': value.termDoneKey,
         },
       );
  final AccountPreferences<YgdkReminderSettings> _store;
  static YgdkReminderSettings _decode(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.length != 3 ||
        value['enabled'] is! bool ||
        (value['weekDoneKey'] != null && value['weekDoneKey'] is! String) ||
        (value['termDoneKey'] != null && value['termDoneKey'] is! String)) {
      throw const FormatException('提醒偏好无效');
    }
    return YgdkReminderSettings(
      enabled: value['enabled'] as bool,
      weekDoneKey: value['weekDoneKey'] as String?,
      termDoneKey: value['termDoneKey'] as String?,
    );
  }

  @override
  Future<YgdkReminderSettings> read(String account) async =>
      await _store.read(account) ?? const YgdkReminderSettings();
  @override
  Future<void> write(String account, YgdkReminderSettings value) =>
      _store.write(account, value);
  @override
  Future<void> clear(String account) => _store.clear(account);
}
