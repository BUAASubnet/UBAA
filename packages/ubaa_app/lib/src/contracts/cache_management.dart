import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
export 'package:ubaa_domain/ubaa_domain.dart'
    show CacheUsageSummary, CacheClearOutcome, CacheMaintenanceFailure;

/// 管理操作必须带上确认时的本机账号标识，防止切换账号后的迟到确认。
abstract interface class CacheManagementBackend {
  Future<CacheUsageSummary> cacheUsage({required String accountId});
  Future<CacheClearOutcome> clearBusinessCache({required String accountId});
}

/// 只在显式确认后从保险箱重新取得密钥，不能作为open失败的自动回退。
abstract interface class CacheRecoveryBackend
    implements CacheManagementBackend {
  Future<CacheClearOutcome> clearOrRebuildBusinessCache({
    required LocalAccount account,
    required List<int> key,
  });
}
