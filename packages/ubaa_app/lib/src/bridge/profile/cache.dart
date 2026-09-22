part of '../bridge_backend.dart';

Future<OfflineProfileRead> _readCachedProfile(
  BridgeBackend backend,
  RoutePolicy policy,
) async {
  await backend._offlineTail;
  final cache = backend._offlineCache, account = backend._offlineAccount;
  if (cache == null || account == null) return const OfflineProfileRead(null);
  final routes = switch (policy) {
    RoutePolicy.direct => [BridgeConnectionMode.direct],
    RoutePolicy.webvpn => [BridgeConnectionMode.webVpn],
    RoutePolicy.auto => [
      BridgeConnectionMode.direct,
      BridgeConnectionMode.webVpn,
    ],
  };
  CachedProfile? newest;
  BackendException? failure;
  for (final route in routes) {
    try {
      final value = await cache.readProfile(route: route);
      if (value == null) continue;
      if (value.sourceRoute != route)
        throw const BackendException(UbaaErrorCode.operationConflict);
      final projection = CachedProfile(
        accountId: account.id,
        route: _toConnectionMode(route),
        fetchedAt: _cacheTime(value.fetchedAt.toInt()),
        complete: value.complete,
        maskedUsername: value.data.maskedUsername,
        maskedName: value.data.maskedName,
        maskedSchoolId: value.data.maskedSchoolId,
      );
      if (newest == null || projection.fetchedAt.isAfter(newest.fetchedAt))
        newest = projection;
    } on BridgeError catch (error) {
      failure ??= _mapError(error);
    } on BackendException catch (error) {
      failure ??= error;
    }
  }
  if (backend._offlineAccount?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  return OfflineProfileRead(newest, error: failure);
}

Future<ProfileRefresh> _refreshProfile(
  BridgeBackend backend,
  LocalAccount expectedAccount,
) async {
  await backend._offlineTail;
  final cache = backend._offlineCache, account = backend._offlineAccount;
  void checkOwner() {
    final owner = backend._offlineAccount;
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
      fetchedAt = _cacheTime(value.fetchedAt.toInt());
      saved = value.savedForOffline;
    }
    checkOwner();
    final profile = _profileSummary(data);
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
      route: _toConnectionMode(decision.resolvedRoute),
      evidence: DataEvidence(
        accountId: expectedAccount.id,
        origin: DataOrigin.online,
        fetchedAt: fetchedAt,
        complete: true,
        savedForOffline: saved,
      ),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}
