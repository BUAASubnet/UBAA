import 'package:ubaa_domain/ubaa_domain.dart';

import 'preferences.dart';

/// 研讨室预约表单的上一次填写内容，按账号隔离。
abstract interface class CgyyReservationDefaultsStore {
  Future<CgyyReservationDefaults?> read(String account);
  Future<void> write(String account, CgyyReservationDefaults value);
  Future<void> clearAccount(String account);
}

/// 固定错误不保留账号、联系电话或系统异常。
final class CgyyReservationDefaultsStoreException implements Exception {
  const CgyyReservationDefaultsStoreException();
  @override
  String toString() => '研讨室预约记忆存储失败';
}

/// 测试与显式 backend 使用的内存实现。
final class MemoryCgyyReservationDefaultsStore
    implements CgyyReservationDefaultsStore {
  final _values = <String, CgyyReservationDefaults>{};

  @override
  Future<CgyyReservationDefaults?> read(String account) async =>
      _values[account];

  @override
  Future<void> write(String account, CgyyReservationDefaults value) async {
    _values[account] = value;
  }

  @override
  Future<void> clearAccount(String account) async => _values.remove(account);
}

/// 按用户选择与普通偏好同等保存；账号作用域由统一偏好层隔离。
final class PreferencesCgyyReservationDefaultsStore
    implements CgyyReservationDefaultsStore {
  PreferencesCgyyReservationDefaultsStore({
    required String scope,
    PreferenceValues? values,
  }) : _store = AccountPreferences(
         scope: scope,
         kind: 'cgyy-defaults',
         values: values,
         decode: _decode,
         encode: _encode,
       );
  final AccountPreferences<CgyyReservationDefaults> _store;

  static CgyyReservationDefaults _decode(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    String text(String field) => switch (value[field]) {
      final String s => s,
      null => '',
      _ => throw const FormatException(),
    };
    bool flag(String field) => switch (value[field]) {
      final bool b => b,
      null => false,
      _ => throw const FormatException(),
    };
    final purpose = value['purposeType'];
    if (purpose != null && (purpose is! int || purpose <= 0))
      throw const FormatException();
    return CgyyReservationDefaults(
      phone: text('phone'),
      theme: text('theme'),
      purposeType: purpose as int?,
      joinerNum: text('joinerNum'),
      activityContent: text('activityContent'),
      joiners: text('joiners'),
      isPhilosophySocialSciences: flag('philosophy'),
      isOffSchoolJoiner: flag('offSchool'),
    );
  }

  static Object _encode(CgyyReservationDefaults value) => {
    'phone': value.phone,
    'theme': value.theme,
    'purposeType': value.purposeType,
    'joinerNum': value.joinerNum,
    'activityContent': value.activityContent,
    'joiners': value.joiners,
    'philosophy': value.isPhilosophySocialSciences,
    'offSchool': value.isOffSchoolJoiner,
  };

  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object {
      throw const CgyyReservationDefaultsStoreException();
    }
  }

  @override
  Future<CgyyReservationDefaults?> read(String account) =>
      _safe(() => _store.read(account));

  @override
  Future<void> write(String account, CgyyReservationDefaults value) =>
      _safe(() => _store.write(account, value));

  @override
  Future<void> clearAccount(String account) =>
      _safe(() => _store.clear(account));
}
