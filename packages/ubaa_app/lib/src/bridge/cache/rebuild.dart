part of 'lifecycle.dart';

Future<CacheClearOutcome> bridgeClearOrRebuildBusinessCache(
  BridgeContext backend,
  LocalAccount account,
  List<int> key,
) async {
  void checkOwner() {
    if (backend.closed ||
        backend.cache.targetAccountId != account.id ||
        (backend.cache.account != null &&
            backend.cache.account!.id != account.id)) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
  }

  checkOwner();
  final directory = backend.configDirectory;
  if (directory == null)
    throw const BackendException(UbaaErrorCode.unsupported);
  backend.cache.generation++;
  return bridgeOfflineSerial(backend, () async {
    checkOwner();
    try {
      final binding = backend.sharedAccount;
      if (binding != null) await bridgeValidateSharedBinding(binding);
      checkOwner();
      if (binding != null && binding.account.id != account.id)
        throw const BackendException(UbaaErrorCode.operationConflict);
      final native = backend.nativeAccount;
      if (binding != null && native == null)
        throw const BackendException(UbaaErrorCode.operationConflict);
      final result = native == null
          ? await BridgeOfflineCache.clearOrRebuild(
              configDir: directory,
              accountId: account.id,
              expectedIdentity: account.username,
              key: key,
            )
          : await BridgeOfflineCache.clearOrRebuildShared(
              configDir: directory,
              accountId: account.id,
              expectedIdentity: account.username,
              key: key,
              scope: native,
            );
      // 即使初始化失败，清空已提交；不能继续沿用原句柄或声称可离线保存。
      backend.cache.handle = result.cache;
      backend.cache.account = account;
      await bridgeCommitSharedBinding(binding);
      checkOwner();
      return bridgeCacheClearOutcome(
        result.report,
        account.id,
        cacheReady: result.cache != null,
      );
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  });
}
