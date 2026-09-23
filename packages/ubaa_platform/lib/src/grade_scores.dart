import 'dart:convert';
import 'dart:io';
import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class GradeScoreStore {
  /// 保存本次完整观察，返回同账号、路线、学期的原基线。
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  );
  Future<void> clearAccount(String account);
}

final class MemoryGradeScoreStore implements GradeScoreStore {
  final _values = <(String, ConnectionMode, String), GradeScoreBaseline>{};
  Future<GradeScoreBaseline?> read(
    String account,
    ConnectionMode route, {
    String? term,
  }) async => term == null
      ? _values.entries
            .where((entry) => entry.key.$1 == account && entry.key.$2 == route)
            .lastOrNull
            ?.value
      : _values[(account, route, term)];
  Future<void> write(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) async {
    if (value.scores.isNotEmpty)
      _values[(account, route, value.termCode)] = _freeze(value);
  }

  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) async {
    final key = (account, route, value.termCode),
        previous = _values[(account, route, value.termCode)];
    if (value.scores.isNotEmpty) _values[key] = _freeze(value);
    return previous;
  }

  @override
  Future<void> clearAccount(String account) async {
    _values.removeWhere((key, _) => key.$1 == account);
  }
}

GradeScoreBaseline _freeze(GradeScoreBaseline value) => GradeScoreBaseline(
  termCode: value.termCode,
  termName: value.termName,
  scores: List.unmodifiable(value.scores),
);

/// 仅用于迁移和显式清理旧明文；新观察必须交给Core加密仓库。
final class FileGradeScoreStore {
  FileGradeScoreStore(this.file);
  final File file;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _checkAccount(String account) {
    if (account.trim().isEmpty) throw ArgumentError('成绩基线账号标识不能为空');
  }

  Future<String?> _raw() async =>
      await file.exists() ? await file.readAsString() : null;
  Map<String, Map<String, GradeScoreBaseline>> _decode(String? raw) {
    if (raw == null) return {};
    final Object? data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['schema'] != 1 ||
        data['accounts'] is! Map<String, dynamic>) {
      throw const FormatException('成绩基线格式无效');
    }
    final accounts = <String, Map<String, GradeScoreBaseline>>{};
    for (final account in (data['accounts'] as Map<String, dynamic>).entries) {
      final routes = account.value;
      if (account.key.trim().isEmpty || routes is! Map<String, dynamic>) {
        throw const FormatException('成绩基线账号字段无效');
      }
      accounts[account.key] = {};
      for (final scope in routes.entries) {
        final value = scope.value;
        if (!ConnectionMode.values.any((route) => route.name == scope.key) ||
            value is! Map<String, dynamic> ||
            value['termCode'] is! String ||
            (value['termCode'] as String).trim().isEmpty ||
            value['termName'] is! String ||
            value['scores'] is! List)
          throw const FormatException('成绩基线路线或学期字段无效');
        final scores = <GradeScoreEntry>[];
        for (final entry in value['scores'] as List) {
          if (entry is! Map<String, dynamic> ||
              entry['key'] is! String ||
              (entry['key'] as String).trim().isEmpty ||
              ['courseName', 'courseCode', 'score'].any(
                (field) => entry[field] != null && entry[field] is! String,
              )) {
            throw const FormatException('成绩基线条目字段无效');
          }
          scores.add(
            GradeScoreEntry(
              key: entry['key'] as String,
              courseName: entry['courseName'] as String?,
              courseCode: entry['courseCode'] as String?,
              score: entry['score'] as String?,
            ),
          );
        }
        accounts[account.key]![scope.key] = GradeScoreBaseline(
          termCode: value['termCode'] as String,
          termName: value['termName'] as String,
          scores: List.unmodifiable(scores),
        );
      }
    }
    return accounts;
  }

  Future<void> _save(
    Map<String, Map<String, GradeScoreBaseline>> accounts,
  ) async {
    await file.parent.create(recursive: true);
    final folder = await file.parent.createTemp('.grade-scores-');
    final temporary = File('${folder.path}/baseline.json');
    try {
      await temporary.create();
      if (Platform.isMacOS || Platform.isLinux) {
        final permission = await Process.run('chmod', ['600', temporary.path]);
        if (permission.exitCode != 0)
          throw const FileSystemException('无法设置成绩基线私有权限');
      }
      await temporary.writeAsString(
        jsonEncode({
          'schema': 1,
          'accounts': {
            for (final account in accounts.entries)
              account.key: {
                for (final scope in account.value.entries)
                  scope.key: {
                    'termCode': scope.value.termCode,
                    'termName': scope.value.termName,
                    'scores': [
                      for (final score in scope.value.scores)
                        {
                          'key': score.key,
                          'courseName': score.courseName,
                          'courseCode': score.courseCode,
                          'score': score.score,
                        },
                    ],
                  },
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

  Future<GradeScoreBaseline?> read(String account, ConnectionMode route) =>
      _serial(() async {
        _checkAccount(account);
        return _decode(await _raw())[account]?[route.name];
      });
  Future<void> write(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) async => throw UnsupportedError('新的成绩基线必须加密保存');

  Future<void> clearAccount(String account) => _serial(() async {
    _checkAccount(account);
    final data = _decode(await _raw());
    if (data.remove(account) != null) await _saveRemaining(data);
  });

  /// 本地串行迁移；保存失败时原文件原样保留，成功只移除迁入的范围。
  Future<T> migrate<T>(
    String account,
    ConnectionMode route,
    Future<T> Function(GradeScoreBaseline? legacy) saveEncrypted,
  ) => _serial(() async {
    _checkAccount(account);
    final original = await _raw();
    final data = _decode(original);
    final legacy = data[account]?[route.name];
    final result = await saveEncrypted(legacy);
    if (legacy != null) {
      if (await _raw() != original)
        throw const FileSystemException('旧成绩基线已变化，保留文件等待重试');
      data[account]!.remove(route.name);
      if (data[account]!.isEmpty) data.remove(account);
      await _saveRemaining(data);
    }
    return result;
  });

  Future<void> _saveRemaining(
    Map<String, Map<String, GradeScoreBaseline>> data,
  ) async {
    if (data.isEmpty) {
      if (await file.exists()) await file.delete();
    } else {
      await _save(data);
    }
  }
}
