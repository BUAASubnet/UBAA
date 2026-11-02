import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import '../../contracts/backend.dart';
import '../context.dart';
import '../cache/lifecycle.dart' show bridgeOfflineSerial;
import '../support/mapping.dart' show bridgeMapError;

/// 清理票据只传给指定操作，不装入普通客户端或库句柄的活动归属。
Future<void> bridgeSharedLogout(
  BridgeContext backend,
  SharedAccountBinding revoked, {
  required bool clearCache,
}) async {
  if (backend.closed || !revoked.isRevocation)
    throw const BackendException(UbaaErrorCode.operationConflict);
  await revoked.validate();
  final native = await BridgeSharedAccount.capture(
    directory: revoked.directory,
    generation: BigInt.from(revoked.generation),
  );
  (Object, StackTrace)? failure;
  Future<void> attempt(Future<void> Function() action) async {
    try {
      await action();
    } on BridgeError catch (error, stack) {
      failure ??= (bridgeMapError(error), stack);
    } on Object catch (error, stack) {
      failure ??= (error, stack);
    }
  }

  backend.cache.generation++;
  backend.cache.targetAccountId = null;
  try {
    if (clearCache)
      await attempt(() async {
        final key = await revoked.accounts.materials.coordinate(() async {
          await revoked.validate();
          return revoked.accounts.cacheKey(revoked.account);
        });
        try {
          final directory = backend.configDirectory;
          if (directory == null)
            throw const BackendException(UbaaErrorCode.unsupported);
          final result = await BridgeOfflineCache.clearOrRebuildShared(
            configDir: directory,
            accountId: revoked.account.id,
            expectedIdentity: revoked.account.username,
            key: key,
            scope: native,
          );
          try {
            if (result.report.maintenanceError != null)
              throw const BackendException(UbaaErrorCode.internalError);
          } finally {
            await result.cache?.close();
            result.cache?.dispose();
          }
        } finally {
          key.fillRange(0, key.length, 0);
        }
      });
    await attempt(() => backend.client.logoutWithSharedAccount(scope: native));
  } finally {
    await attempt(
      () => bridgeOfflineSerial(backend, () async {
        final cache = backend.cache.handle;
        backend.cache.handle = null;
        backend.cache.account = null;
        await cache?.close();
        cache?.dispose();
        backend.nativeAccount?.dispose();
        backend.nativeAccount = null;
      }),
    );
    native.dispose();
  }
  if (failure case final value?) Error.throwWithStackTrace(value.$1, value.$2);
}
