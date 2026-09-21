import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'backend.dart';

/// 独立于网络会话的本地读取；不恢复写动作或在线资格。
abstract interface class OfflineCacheBackend {
  Future<void> openOfflineAccount(LocalAccount account, List<int> key);
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy);
  Future<void> deactivateOfflineAccount();
  Future<void> clearOfflineAccount();
}

/// 本地范围可部分可用；单条损坏不能遮蔽其他已保存内容。
final class OfflineHomeRead extends Iterable<CachedFeatureProjection> {
  OfflineHomeRead(Iterable<CachedFeatureProjection> values, {this.error})
    : _values = List.unmodifiable(values);
  final List<CachedFeatureProjection> _values;
  final BackendException? error;
  @override
  Iterator<CachedFeatureProjection> get iterator => _values.iterator;
}

/// 精确查询的独立本地通道，不受认证或网络队列阻塞。
abstract interface class OfflineQueryBackend {
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  );
}

final class OfflineQueryRead {
  const OfflineQueryRead(this.projection, {this.error});
  final CachedFeatureProjection? projection;
  final BackendException? error;
}
