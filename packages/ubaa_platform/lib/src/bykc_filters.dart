import 'infrastructure/preferences.dart';
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

/// 普通筛选偏好交给平台插件，账号作用域由统一偏好层隔离。
final class PreferencesBykcCourseFilterStore implements BykcCourseFilterStore {
  PreferencesBykcCourseFilterStore({
    required String scope,
    PreferenceValues? values,
  }) : _store = AccountPreferences(
         scope: scope,
         kind: 'bykc',
         values: values,
         decode: _decode,
         encode: _encode,
       );
  final AccountPreferences<BykcCourseFilters> _store;
  static BykcCourseFilters _decode(Object? value) {
    if (value is! Map<String, dynamic> || value.length != 3)
      throw const FormatException();
    List<String> strings(String field) {
      final items = value[field];
      if (items is! List || items.any((item) => item is! String))
        throw const FormatException();
      return items.cast<String>();
    }

    final statuses = <BykcCourseStatus>[];
    for (final name in strings('statuses')) {
      final matches = BykcCourseStatus.values.where((s) => s.name == name);
      if (matches.isEmpty) throw const FormatException();
      statuses.add(matches.single);
    }
    try {
      return BykcCourseFilters(
        statuses: statuses,
        categories: strings('categories'),
        campuses: strings('campuses'),
      );
    } on ArgumentError {
      throw const FormatException();
    }
  }

  static Object _encode(BykcCourseFilters value) => {
    'statuses': [
      for (final s in BykcCourseStatus.values)
        if (value.statuses.contains(s)) s.name,
    ],
    'categories': value.categories.toList()..sort(),
    'campuses': value.campuses.toList()..sort(),
  };
  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FormatException {
      throw const BykcCourseFilterStoreException(
        BykcCourseFilterStoreError.invalidData,
      );
    } on Object {
      throw const BykcCourseFilterStoreException(
        BykcCourseFilterStoreError.storageFailure,
      );
    }
  }

  @override
  Future<BykcCourseFilters?> read(String account) =>
      _safe(() => _store.read(account));
  @override
  Future<void> write(String account, BykcCourseFilters value) =>
      _safe(() => _store.write(account, value));
  @override
  Future<void> clearAccount(String account) =>
      _safe(() => _store.clear(account));
}
