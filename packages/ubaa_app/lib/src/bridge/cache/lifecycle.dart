import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../support/mapping.dart'
    show bridgeCacheClearOutcome, bridgeCacheUsageSummary, bridgeMapError;
part 'rebuild.dart';
part 'account.dart';

// Zone 只携带代际值，不建立错误 Zone；Core 仍负责事务内的持久化屏障。
Future<T> bridgeWithOfflineRead<T>(
  BridgeContext backend,
  Future<T> Function() read,
) {
  final generation =
      Zone.current[backend.cache.scopeKey] as int? ?? backend.cache.generation;
  return runZoned(() async {
    bridgeCheckOfflineGeneration(backend, generation);
    try {
      return await read();
    } finally {
      // 迟到的成功或错误均不属于新一代，避免旧认证错误干扰当前账号。
      bridgeCheckOfflineGeneration(backend, generation);
    }
  }, zoneValues: {backend.cache.scopeKey: generation});
}

void bridgeCheckOfflineGeneration(BridgeContext backend, int generation) {
  if (backend.cache.generation != generation) {
    throw const BackendException(UbaaErrorCode.operationConflict);
  }
}

Future<void> bridgeAwaitOfflineScope(BridgeContext backend) async {
  final generation =
      Zone.current[backend.cache.scopeKey] as int? ?? backend.cache.generation;
  bridgeCheckOfflineGeneration(backend, generation);
  await backend.cache.tail;
  bridgeCheckOfflineGeneration(backend, generation);
}

BridgeOfflineCache bridgeManagementCache(
  BridgeContext backend,
  String accountId,
) {
  final cache = backend.cache.handle;
  if (cache == null ||
      backend.cache.account?.id != accountId ||
      backend.cache.targetAccountId != accountId) {
    throw const BackendException(UbaaErrorCode.operationConflict);
  }
  return cache;
}

Future<CacheUsageSummary> bridgeCacheUsage(
  BridgeContext backend,
  String accountId,
) => bridgeWithOfflineRead(backend, () async {
  await bridgeAwaitOfflineScope(backend);
  try {
    final usage = await bridgeManagementCache(backend, accountId).usage();
    return bridgeCacheUsageSummary(usage, accountId);
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
});

Future<CacheClearOutcome> bridgeClearBusinessCache(
  BridgeContext backend,
  String accountId,
) async {
  bridgeManagementCache(backend, accountId);
  backend.cache.generation++;
  return bridgeOfflineSerial(backend, () async {
    try {
      final old = bridgeManagementCache(backend, accountId);
      final reset = await old.clearAndReopen();
      backend.cache.handle = reset.cache;
      return bridgeCacheClearOutcome(reset.report, accountId);
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  });
}
