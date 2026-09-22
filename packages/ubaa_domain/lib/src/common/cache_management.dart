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
