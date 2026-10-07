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
  final previous = backend.cache.targetAccountId ?? backend.cache.account?.id;
  if (previous != null && previous != account.id) backend.cache.generation++;
  backend.cache.targetAccountId = account.id;
  return bridgeOfflineSerial(backend, () async {
    final directory = backend.configDirectory;
    if (directory == null)
      throw const BackendException(UbaaErrorCode.unsupported);
    try {
      if (backend.cache.account?.id != account.id) {
        await backend.cache.handle?.deactivate();
        backend.cache.handle = null;
        backend.cache.account = null;
      }
      final cache = await BridgeOfflineCache.open(
        configDir: directory,
        accountId: account.id,
        expectedIdentity: account.username,
        key: key,
      );
      await cache.activate();
      backend.cache.handle = cache;
      backend.cache.account = account;
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  });
}
