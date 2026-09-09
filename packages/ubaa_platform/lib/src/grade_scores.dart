import 'dart:convert';
import 'dart:io';
import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class GradeScoreStore {
  Future<GradeScoreBaseline?> read(String account, ConnectionMode route);
  Future<void> write(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  );
  Future<void> clearAccount(String account);
}

final class MemoryGradeScoreStore implements GradeScoreStore {
  final _values = <(String, ConnectionMode), GradeScoreBaseline>{};
  @override
  Future<GradeScoreBaseline?> read(
    String account,
    ConnectionMode route,
  ) async => _values[(account, route)];
  @override
  Future<void> write(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) async {
    _values[(account, route)] = _freeze(value);
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

/// 只保存变化检查所需的派生成绩基线；独立于Core配置、会话及原始响应。
final class FileGradeScoreStore implements GradeScoreStore {
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

  Future<Map<String, Map<String, GradeScoreBaseline>>> _readAll() async {
    if (!await file.exists()) return {};
    final Object? data = jsonDecode(await file.readAsString());
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

  @override
  Future<GradeScoreBaseline?> read(String account, ConnectionMode route) =>
      _serial(() async {
        _checkAccount(account);
        return (await _readAll())[account]?[route.name];
      });
  @override
  Future<void> write(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) {
    final stable = _freeze(value);
    return _serial(() async {
      _checkAccount(account);
      final data = await _readAll();
      (data[account] ??= {})[route.name] = stable;
      await _save(data);
    });
  }

  @override
  Future<void> clearAccount(String account) => _serial(() async {
    _checkAccount(account);
    final data = await _readAll();
    data.remove(account);
    await _save(data);
  });
}
