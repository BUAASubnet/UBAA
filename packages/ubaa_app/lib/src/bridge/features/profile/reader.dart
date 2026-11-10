import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeMapError,
        bridgeProfileSummary,
        bridgeToConnectionMode;

Future<OfflineProfileRead> bridgeReadCachedProfile(
  BridgeContext backend,
  RoutePolicy policy,
) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
  if (cache == null || account == null) return const OfflineProfileRead(null);
  CachedProfile? projection;
  BackendException? failure;
  try {
    final value = await cache.readProfile(route: BridgeConnectionMode.direct);
    if (value != null) {
      projection = CachedProfile(
        accountId: account.id,
        route: bridgeToConnectionMode(value.sourceRoute),
        fetchedAt: bridgeCacheTime(value.fetchedAt.toInt()),
        complete: value.complete,
        profile:
            bridgeProfileSummary(value.data) ??
            UserSummary(
              username: value.data.schoolId ?? '本机账号',
              displayName: value.data.name,
              schoolId: value.data.schoolId,
              email: value.data.email,
              phone: value.data.phone,
            ),
      );
    }
  } on BridgeError catch (error) {
    failure = bridgeMapError(error);
  } on BackendException catch (error) {
    failure = error;
  }
  if (backend.cache.account?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  return OfflineProfileRead(projection, error: failure);
}

Future<ProfileRefresh> bridgeRefreshProfile(
  BridgeContext backend,
  LocalAccount expectedAccount,
) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
  void checkOwner() {
    final owner = backend.cache.account;
    if (owner != null && owner.id != expectedAccount.id)
      throw const BackendException(UbaaErrorCode.operationConflict);
  }

  checkOwner();
  try {
    BridgeUserProfile data;
    BridgeRouteDecision decision;
    DateTime fetchedAt;
    bool saved;
    if (cache == null || account == null) {
      // 密钥或存储不可用时保留原只读能力；不另建明文资料文件。
      final value = await backend.client.userInfo();
      data = value.data;
      decision = value.route;
      fetchedAt = DateTime.now();
      saved = false;
    } else {
      final value = await backend.client.userInfoCached(cache: cache);
      data = value.data;
      decision = value.route;
      fetchedAt = bridgeCacheTime(value.fetchedAt.toInt());
      saved = value.savedForOffline;
    }
    checkOwner();
    final profile = bridgeProfileSummary(data);
    if (profile == null)
      throw const BackendException(UbaaErrorCode.upstreamChanged);
    if (profile.username != expectedAccount.username &&
        profile.schoolId != expectedAccount.username) {
      throw const BackendException(
        UbaaErrorCode.authenticationRequired,
        accountMismatch: true,
      );
    }
    return ProfileRefresh(
      profile: profile,
      route: bridgeToConnectionMode(decision.resolvedRoute),
      evidence: DataEvidence(
        accountId: expectedAccount.id,
        origin: DataOrigin.online,
        fetchedAt: fetchedAt,
        complete: true,
        savedForOffline: saved,
      ),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}
