import 'package:ubaa_domain/ubaa_domain.dart';
export 'package:ubaa_domain/ubaa_domain.dart'
    show CacheUsageSummary, CacheClearOutcome, CacheMaintenanceFailure;

/// 管理操作必须带上确认时的本机账号标识，防止切换账号后的迟到确认。
abstract interface class CacheManagementBackend {
  Future<CacheUsageSummary> cacheUsage({required String accountId});
  Future<CacheClearOutcome> clearBusinessCache({required String accountId});
}
