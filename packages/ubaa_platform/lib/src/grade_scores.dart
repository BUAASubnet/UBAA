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
