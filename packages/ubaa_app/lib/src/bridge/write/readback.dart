part of 'operations.dart';

Future<List<WriteReadbackHint>> bridgeReadWriteReadbackHints(
  BridgeContext backend,
  String accountId,
) => bridgeWithOfflineRead(backend, () async {
  await bridgeAwaitOfflineScope(backend);
  try {
    final values = await bridgeManagementCache(
      backend,
      accountId,
    ).writeReadbackHints();
    final ids = <String>{};
    return List.unmodifiable(
      values.map((value) {
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value.id) ||
            !ids.add(value.id) ||
            value.startedAt <= 0)
          throw const BackendException(
            UbaaErrorCode.internalError,
            cacheFailure: CacheMaintenanceFailure.corrupt,
          );
        return WriteReadbackHint(
          id: value.id,
          operation: bridgeToWriteOperation(value.operation),
          route: bridgeToConnectionMode(value.route),
          startedAt: bridgeCacheTime(value.startedAt.toInt()),
        );
      }),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
});

Future<void> bridgeDismissWriteReadbackHint(
  BridgeContext backend,
  String accountId,
  String id,
) => bridgeWithOfflineRead(backend, () async {
  await bridgeAwaitOfflineScope(backend);
  try {
    await bridgeManagementCache(
      backend,
      accountId,
    ).dismissWriteReadback(id: id);
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
});
