part of '../bridge_backend.dart';

// Zone 只携带代际值，不建立错误 Zone；Core 仍负责事务内的持久化屏障。
Future<T> _withOfflineRead<T>(
  BridgeBackend backend,
  Future<T> Function() read,
) {
  final generation =
      Zone.current[backend._offlineScopeKey] as int? ??
      backend._offlineGeneration;
  return runZoned(() async {
    _checkOfflineGeneration(backend, generation);
    try {
      return await read();
    } finally {
      // 迟到的成功或错误均不属于新一代，避免旧认证错误干扰当前账号。
      _checkOfflineGeneration(backend, generation);
    }
  }, zoneValues: {backend._offlineScopeKey: generation});
}

void _checkOfflineGeneration(BridgeBackend backend, int generation) {
  if (backend._offlineGeneration != generation) {
    throw const BackendException(UbaaErrorCode.operationConflict);
  }
}

Future<void> _awaitOfflineScope(BridgeBackend backend) async {
  final generation =
      Zone.current[backend._offlineScopeKey] as int? ??
      backend._offlineGeneration;
  _checkOfflineGeneration(backend, generation);
  await backend._offlineTail;
  _checkOfflineGeneration(backend, generation);
}

BridgeOfflineCache _managementCache(BridgeBackend backend, String accountId) {
  final cache = backend._offlineCache;
  if (cache == null ||
      backend._offlineAccount?.id != accountId ||
      backend._offlineTargetAccountId != accountId) {
    throw const BackendException(UbaaErrorCode.operationConflict);
  }
  return cache;
}

Future<CacheUsageSummary> _cacheUsage(
  BridgeBackend backend,
  String accountId,
) => _withOfflineRead(backend, () async {
  await _awaitOfflineScope(backend);
  try {
    final usage = await _managementCache(backend, accountId).usage();
    return _cacheUsageSummary(usage, accountId);
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
});

Future<CacheClearOutcome> _clearBusinessCache(
  BridgeBackend backend,
  String accountId,
) async {
  _managementCache(backend, accountId);
  backend._offlineGeneration++;
  return _offlineSerial(backend, () async {
    try {
      final old = _managementCache(backend, accountId);
      final reset = await old.clearAndReopen();
      backend._offlineCache = reset.cache;
      final report = reset.report;
      return CacheClearOutcome(
        usage: report.usage == null
            ? null
            : _cacheUsageSummary(report.usage!, accountId),
        compacted: report.compacted,
        maintenanceError: switch (report.maintenanceError) {
          null => null,
          BridgeCacheFailure.unavailable => CacheMaintenanceFailure.unavailable,
          BridgeCacheFailure.invalidInput =>
            CacheMaintenanceFailure.invalidInput,
          BridgeCacheFailure.corrupt => CacheMaintenanceFailure.corrupt,
          BridgeCacheFailure.unsupportedVersion =>
            CacheMaintenanceFailure.unsupportedVersion,
          BridgeCacheFailure.inactive => CacheMaintenanceFailure.inactive,
          BridgeCacheFailure.superseded => CacheMaintenanceFailure.superseded,
          BridgeCacheFailure.capacity => CacheMaintenanceFailure.capacity,
        },
      );
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  });
}

CacheUsageSummary _cacheUsageSummary(
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
