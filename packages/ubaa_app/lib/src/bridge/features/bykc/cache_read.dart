part of 'reader.dart';

/// 错详情不得生成动作；只能继续显示同账号、路线和查询的旧只读内容。
Future<FeatureResult> _preserveBykcDetail(
  BridgeContext backend,
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  ConnectionMode route,
) async {
  final old = await bridgeCachedBykcProjection(
    cache,
    account,
    query,
    bridgeToBridgeConnectionMode(route),
  );
  if (backend.cache.account?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  if (old == null)
    throw BackendException(
      UbaaErrorCode.upstreamChanged,
      kind: UbaaErrorKind.upstream,
      retryable: false,
      resolvedRoute: route,
    );
  return FeatureResult.success(
    details: old.details,
    resolvedRoute: old.route,
    evidence: DataEvidence(
      accountId: account.id,
      origin: DataOrigin.persisted,
      fetchedAt: old.fetchedAt,
      complete: false,
      savedForOffline: false,
    ),
  );
}
