part of '../bridge_backend.dart';

Future<CacheClearOutcome> _clearOrRebuildBusinessCache(
  BridgeBackend backend,
  LocalAccount account,
  List<int> key,
) async {
  void checkOwner() {
    if (backend._offlineTargetAccountId != account.id ||
        (backend._offlineAccount != null &&
            backend._offlineAccount!.id != account.id)) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
  }

  checkOwner();
  final directory = backend.configDirectory;
  if (directory == null)
    throw const BackendException(UbaaErrorCode.unsupported);
  backend._offlineGeneration++;
  return _offlineSerial(backend, () async {
    checkOwner();
    try {
      final result = await BridgeOfflineCache.clearOrRebuild(
        configDir: directory,
        accountId: account.id,
        expectedIdentity: account.username,
        key: key,
      );
      // 即使初始化失败，清空已提交；不能继续沿用原句柄或声称可离线保存。
      backend._offlineCache = result.cache;
      backend._offlineAccount = account;
      return _cacheClearOutcome(
        result.report,
        account.id,
        cacheReady: result.cache != null,
      );
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  });
}
