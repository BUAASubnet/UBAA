import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 独立于网络会话的本地读取；不恢复写动作或在线资格。
abstract interface class OfflineCacheBackend {
  Future<void> openOfflineAccount(LocalAccount account, List<int> key);
  Future<List<CachedFeatureProjection>> readCachedHome(RoutePolicy policy);
  Future<void> deactivateOfflineAccount();
  Future<void> clearOfflineAccount();
}
