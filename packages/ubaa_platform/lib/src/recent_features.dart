import 'package:ubaa_domain/ubaa_domain.dart';
import 'infrastructure/preferences.dart';

/// 只保存功能标识的本机导航偏好，不保存页面内容或查询参数。
abstract interface class RecentFeatureStore {
  Future<List<FeatureId>> read(String account);
  Future<void> write(String account, List<FeatureId> features);
  Future<void> clearAccount(String account);
}

final class MemoryRecentFeatureStore implements RecentFeatureStore {
  final _values = <String, List<FeatureId>>{};
  @override
  Future<List<FeatureId>> read(String account) async =>
      _values[account] ?? const [];
  @override
  Future<void> write(String account, List<FeatureId> features) async {
    _values[account] = List.unmodifiable(features.toSet().take(4));
  }

  @override
  Future<void> clearAccount(String account) async => _values.remove(account);
}

final class PreferencesRecentFeatureStore implements RecentFeatureStore {
  PreferencesRecentFeatureStore({
    required String scope,
    PreferenceValues? values,
  }) : _store = AccountPreferences(
         scope: scope,
         kind: 'recent_features',
         values: values,
         decode: _decode,
         encode: (features) => features.map((f) => f.name).toList(),
       );
  final AccountPreferences<List<FeatureId>> _store;
  static List<FeatureId> _decode(Object? value) {
    if (value is! List || value.any((v) => v is! String)) {
      throw const FormatException('功能访问记录格式无效');
    }
    final byName = {for (final f in FeatureId.values) f.name: f};
    // 忽略后续版本移除的入口，并保留已知入口的原始顺序。
    return List.unmodifiable(
      value.map((v) => byName[v]).whereType<FeatureId>().toSet().take(4),
    );
  }

  @override
  Future<List<FeatureId>> read(String account) async =>
      await _store.read(account) ?? const [];
  @override
  Future<void> write(String account, List<FeatureId> features) =>
      _store.write(account, List.unmodifiable(features.toSet().take(4)));
  @override
  Future<void> clearAccount(String account) => _store.clear(account);
}
