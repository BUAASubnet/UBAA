import 'dart:io';
import 'dart:convert';
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

/// 只保存UI提醒偏好，独立于Core配置与会话文件。
final class FileYgdkReminderStore implements YgdkReminderStore {
  FileYgdkReminderStore(this.file);
  final File file;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  void _checkKey(String key) {
    if (key.trim().isEmpty) throw ArgumentError('提醒账号标识不能为空');
  }

  Future<Map<String, YgdkReminderSettings>> _readAll() async {
    if (!await file.exists()) return {};
    final Object? data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic> ||
        data['schema'] != 1 ||
        data['accounts'] is! Map<String, dynamic>)
      throw const FormatException('提醒设置格式无效');
    final result = <String, YgdkReminderSettings>{};
    for (final entry in (data['accounts'] as Map<String, dynamic>).entries) {
      final value = entry.value;
      if (entry.key.trim().isEmpty ||
          value is! Map<String, dynamic> ||
          value['enabled'] is! bool ||
          (value['weekDoneKey'] != null && value['weekDoneKey'] is! String) ||
          (value['termDoneKey'] != null && value['termDoneKey'] is! String)) {
        throw const FormatException('提醒设置字段无效');
      }
      result[entry.key] = YgdkReminderSettings(
        enabled: value['enabled'] as bool,
        weekDoneKey: value['weekDoneKey'] as String?,
        termDoneKey: value['termDoneKey'] as String?,
      );
    }
    return result;
  }

  Future<void> _save(Map<String, YgdkReminderSettings> data) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.pending');
    await temporary.writeAsString(
      jsonEncode({
        'schema': 1,
        'accounts': {
          for (final entry in data.entries)
            entry.key: {
              'enabled': entry.value.enabled,
              'weekDoneKey': entry.value.weekDoneKey,
              'termDoneKey': entry.value.termDoneKey,
            },
        },
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  @override
  Future<YgdkReminderSettings> read(String key) => _serial(() async {
    _checkKey(key);
    return (await _readAll())[key] ?? const YgdkReminderSettings();
  });
  @override
  Future<void> write(String key, YgdkReminderSettings value) =>
      _serial(() async {
        _checkKey(key);
        final data = await _readAll();
        data[key] = value;
        await _save(data);
      });
  @override
  Future<void> clear(String key) => _serial(() async {
    _checkKey(key);
    final data = await _readAll();
    data.remove(key);
    await _save(data);
  });
}
