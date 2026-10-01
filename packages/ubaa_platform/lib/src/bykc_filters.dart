import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class BykcCourseFilterStore {
  Future<BykcCourseFilters?> read(String account);
  Future<void> write(String account, BykcCourseFilters value);
  Future<void> clearAccount(String account);
}

enum BykcCourseFilterStoreError { invalidData, storageFailure }

/// 固定错误不保留账号、路径、JSON 或系统异常。
final class BykcCourseFilterStoreException implements Exception {
  const BykcCourseFilterStoreException(this.code);
  final BykcCourseFilterStoreError code;

  @override
  String toString() => switch (code) {
    BykcCourseFilterStoreError.invalidData => '博雅筛选偏好格式无效',
    BykcCourseFilterStoreError.storageFailure => '博雅筛选偏好存储失败',
  };
}

final class MemoryBykcCourseFilterStore implements BykcCourseFilterStore {
  final _values = <String, BykcCourseFilters>{};

  @override
  Future<BykcCourseFilters?> read(String account) async => _values[account];

  @override
  Future<void> write(String account, BykcCourseFilters value) async {
    _values[account] = value;
  }

  @override
  Future<void> clearAccount(String account) async => _values.remove(account);
}

/// 独立于 Core 配置和会话，仅持久保存三组经过规范化的选择。
final class FileBykcCourseFilterStore implements BykcCourseFilterStore {
  FileBykcCourseFilterStore(this.file);
  final File file;

  // 同一进程中重新创建存储实例也沿用在途顺序，清除不能被旧保存复活。
  static final _tails = <String, Future<void>>{};

  Future<T> _serial<T>(String account, Future<T> Function() action) {
    final key = file.absolute.path;
    final next = (_tails[key] ?? Future<void>.value()).then((_) async {
      try {
        if (account.trim().isEmpty) throw const FormatException();
        return await action();
      } on BykcCourseFilterStoreException {
        rethrow;
      } on FormatException {
        throw const BykcCourseFilterStoreException(
          BykcCourseFilterStoreError.invalidData,
        );
      } on Object {
        throw const BykcCourseFilterStoreException(
          BykcCourseFilterStoreError.storageFailure,
        );
      }
    });
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return next;
  }

  Future<Map<String, BykcCourseFilters>> _readAll() async {
    if (!await file.exists()) return {};
    final Object? data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic> ||
        data.length != 2 ||
        data['schema'] is! int ||
        data['schema'] != 1 ||
        data['accounts'] is! Map<String, dynamic>) {
      throw const FormatException();
    }
    final result = <String, BykcCourseFilters>{};
    for (final entry in (data['accounts'] as Map<String, dynamic>).entries) {
      final value = entry.value;
      if (entry.key.trim().isEmpty ||
          value is! Map<String, dynamic> ||
          value.length != 3) {
        throw const FormatException();
      }
      List<String> strings(String field) {
        final items = value[field];
        if (items is! List || items.any((item) => item is! String)) {
          throw const FormatException();
        }
        return items.cast<String>();
      }

      final statuses = <BykcCourseStatus>[];
      for (final name in strings('statuses')) {
        final matches = BykcCourseStatus.values.where((s) => s.name == name);
        if (matches.isEmpty) throw const FormatException();
        statuses.add(matches.single);
      }
      try {
        result[entry.key] = BykcCourseFilters(
          statuses: statuses,
          categories: strings('categories'),
          campuses: strings('campuses'),
        );
      } on ArgumentError {
        throw const FormatException();
      }
    }
    return result;
  }

  Future<void> _save(Map<String, BykcCourseFilters> accounts) async {
    await file.parent.create(recursive: true);
    final folder = await file.parent.createTemp('.bykc-filters-');
    final temporary = File('${folder.path}/preferences.json');
    try {
      await temporary.create();
      if (Platform.isMacOS || Platform.isLinux) {
        final permission = await Process.run('chmod', ['600', temporary.path]);
        if (permission.exitCode != 0) {
          throw const BykcCourseFilterStoreException(
            BykcCourseFilterStoreError.storageFailure,
          );
        }
      }
      await temporary.writeAsString(
        jsonEncode({
          'schema': 1,
          'accounts': {
            for (final account in accounts.entries)
              account.key: {
                'statuses': [
                  for (final status in BykcCourseStatus.values)
                    if (account.value.statuses.contains(status)) status.name,
                ],
                'categories': account.value.categories.toList()..sort(),
                'campuses': account.value.campuses.toList()..sort(),
              },
          },
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  }

  @override
  Future<BykcCourseFilters?> read(String account) =>
      _serial(account, () async => (await _readAll())[account]);

  @override
  Future<void> write(String account, BykcCourseFilters value) =>
      _serial(account, () async {
        final data = await _readAll();
        data[account] = value;
        await _save(data);
      });

  @override
  Future<void> clearAccount(String account) => _serial(account, () async {
    final data = await _readAll();
    if (data.remove(account) != null) await _save(data);
  });
}
