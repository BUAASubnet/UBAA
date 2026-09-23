part of '../bridge_backend.dart';

Future<List<WriteReadbackHint>> _readWriteReadbackHints(
  BridgeBackend backend,
  String accountId,
) => _withOfflineRead(backend, () async {
  await _awaitOfflineScope(backend);
  try {
    final values = await _managementCache(
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
          operation: _toWriteOperation(value.operation),
          route: _toConnectionMode(value.route),
          startedAt: _cacheTime(value.startedAt.toInt()),
        );
      }),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
});

Future<void> _dismissWriteReadbackHint(
  BridgeBackend backend,
  String accountId,
  String id,
) => _withOfflineRead(backend, () async {
  await _awaitOfflineScope(backend);
  try {
    await _managementCache(backend, accountId).dismissWriteReadback(id: id);
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
});
