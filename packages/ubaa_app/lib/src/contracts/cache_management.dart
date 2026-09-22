/// 管理操作必须带上确认时的本机账号标识，防止切换账号后的迟到确认。
abstract interface class CacheManagementBackend {
  Future<CacheUsageSummary> cacheUsage({required String accountId});
  Future<CacheClearOutcome> clearBusinessCache({required String accountId});
}

final class CacheUsageSummary {
  const CacheUsageSummary({
    required this.accountId,
    required this.entryCount,
    required this.contentBytes,
    required this.databaseBytes,
    required this.reusableBytes,
    required this.softLimitBytes,
    required this.hardLimitBytes,
  });
  final String accountId;
  final int entryCount, contentBytes, databaseBytes, reusableBytes;
  final int softLimitBytes, hardLimitBytes;
}

enum CacheMaintenanceFailure {
  unavailable,
  invalidInput,
  corrupt,
  unsupportedVersion,
  inactive,
  superseded,
  capacity,
}

/// 返回此结果即表示内容清除已提交；空间回收故障不能伪装为事务失败。
final class CacheClearOutcome {
  const CacheClearOutcome({
    this.usage,
    required this.compacted,
    this.maintenanceError,
  });
  final CacheUsageSummary? usage;
  final bool compacted;
  final CacheMaintenanceFailure? maintenanceError;
}
