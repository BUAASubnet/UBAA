part of 'mapping.dart';

CacheUsageSummary bridgeCacheUsageSummary(
  BridgeCacheUsage value,
  String accountId,
) => CacheUsageSummary(
  accountId: accountId,
  entryCount: value.entryCount.toInt(),
  contentBytes: value.contentBytes.toInt(),
  databaseBytes: value.databaseBytes.toInt(),
  reusableBytes: value.reusableBytes.toInt(),
  softLimitBytes: value.softLimitBytes.toInt(),
  hardLimitBytes: value.hardLimitBytes.toInt(),
);

CacheClearOutcome bridgeCacheClearOutcome(
  BridgeCacheClearReport report,
  String accountId, {
  bool cacheReady = true,
}) {
  return CacheClearOutcome(
    cacheReady: cacheReady,
    usage: report.usage == null
        ? null
        : bridgeCacheUsageSummary(report.usage!, accountId),
    compacted: report.compacted,
    maintenanceError: bridgeCacheMaintenanceFailure(report.maintenanceError),
  );
}

CacheMaintenanceFailure? bridgeCacheMaintenanceFailure(
  BridgeCacheFailure? error,
) => switch (error) {
  null => null,
  BridgeCacheFailure.unavailable => CacheMaintenanceFailure.unavailable,
  BridgeCacheFailure.invalidInput => CacheMaintenanceFailure.invalidInput,
  BridgeCacheFailure.corrupt => CacheMaintenanceFailure.corrupt,
  BridgeCacheFailure.unsupportedVersion =>
    CacheMaintenanceFailure.unsupportedVersion,
  BridgeCacheFailure.inactive => CacheMaintenanceFailure.inactive,
  BridgeCacheFailure.superseded => CacheMaintenanceFailure.superseded,
  BridgeCacheFailure.capacity => CacheMaintenanceFailure.capacity,
};
