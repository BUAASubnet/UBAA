part of 'lifecycle.dart';

Future<T> bridgeOfflineSerial<T>(
  BridgeContext backend,
  Future<T> Function() action,
) {
  final next = backend.cache.tail.then((_) => action());
  backend.cache.tail = next.then<void>((_) {}, onError: (Object _) {});
  return next;
}

Future<void> bridgeOpenOfflineAccount(
  BridgeContext backend,
  LocalAccount account,
  List<int> key,
) {
  if (backend.closed)
    return Future<void>.error(
      const BackendException(UbaaErrorCode.operationConflict),
    );
  final previous = backend.cache.targetAccountId ?? backend.cache.account?.id;
  if (previous != null && previous != account.id) backend.cache.generation++;
  backend.cache.targetAccountId = account.id;
  void checkOwner() {
    if (backend.closed || backend.cache.targetAccountId != account.id)
      throw const BackendException(UbaaErrorCode.operationConflict);
  }

  return bridgeOfflineSerial(backend, () async {
    checkOwner();
    final directory = backend.configDirectory;
    if (directory == null)
      throw const BackendException(UbaaErrorCode.unsupported);
    try {
      if (backend.cache.account?.id != account.id) {
        backend.cache.handle?.dispose();
        backend.cache.handle = null;
        backend.cache.account = null;
      }
      final binding = backend.sharedAccount;
      await bridgeValidateSharedBinding(binding);
      checkOwner();
      if (binding != null && binding.account.id != account.id)
        throw const BackendException(UbaaErrorCode.operationConflict);
      final native = backend.nativeAccount;
      if (binding != null && native == null)
        throw const BackendException(UbaaErrorCode.operationConflict);
      final cache = native == null
          ? await BridgeOfflineCache.open(
              configDir: directory,
              accountId: account.id,
              expectedIdentity: account.username,
              key: key,
            )
          : await BridgeOfflineCache.openShared(
              configDir: directory,
              accountId: account.id,
              expectedIdentity: account.username,
              key: key,
              scope: native,
            );
      var adopted = false;
      try {
        checkOwner();
        await cache.activate();
        await bridgeCommitSharedBinding(binding);
        checkOwner();
        backend.cache.handle = cache;
        backend.cache.account = account;
        adopted = true;
      } finally {
        if (!adopted) {
          await cache.close();
          cache.dispose();
        }
      }
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  });
}
