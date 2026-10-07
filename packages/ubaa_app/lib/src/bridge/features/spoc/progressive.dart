part of 'reader.dart';

Future<FeatureReadTask?> bridgeBeginSpocRead(
  BridgeContext backend,
  FeatureQuery? query, {
  LocalAccount? expectedAccount,
}) async {
  final selected = query ?? const FeatureQuery();
  if (selected.view != FeatureQueryView.summary &&
      selected.view != FeatureQueryView.spocDetail)
    return null;
  await bridgeAwaitOfflineScope(backend);
  final generation = backend.cache.generation;
  final account = expectedAccount ?? backend.cache.account;
  final cache = account != null && account.id == backend.cache.account?.id
      ? backend.cache.handle
      : null;
  if (selected.view == FeatureQueryView.spocDetail) {
    return _beginSpocDetailRead(backend, cache, account, selected, generation);
  }
  try {
    final task = cache == null
        ? await backend.client.beginSpocOnline(
            expectedIdentity: account?.username,
          )
        : await backend.client.beginSpocScan(cache: cache);
    try {
      bridgeCheckOfflineGeneration(backend, generation);
    } catch (_) {
      task.cancel();
      rethrow;
    }
    return _SpocFeatureTask(
      backend,
      account,
      cache,
      selected,
      task,
      generation,
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

final class _SpocFeatureTask implements FeatureReadTask {
  _SpocFeatureTask(
    this.backend,
    this.account,
    this.cache,
    this.query,
    this.task,
    this.generation,
  );
  final BridgeContext backend;
  final LocalAccount? account;
  final BridgeOfflineCache? cache;
  final FeatureQuery query;
  final BridgeSpocScan task;
  final int generation;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    task.cancel();
  }

  void _validate() {
    bridgeCheckOfflineGeneration(backend, generation);
    if (_cancelled)
      throw const BackendException(UbaaErrorCode.operationConflict);
  }

  @override
  Future<FeatureReadBatch> next() async {
    _validate();
    try {
      final batch = await backend.client.nextSpocScan(task: task);
      _validate();
      if (batch.completedPages == 0) {
        return const FeatureReadBatch(
          FeatureResult.success(summary: '正在核实作业学期'),
          finished: false,
          publish: false,
        );
      }
      final online = bridgeMapSpocHome(
        batch.result.data,
        bridgeToConnectionMode(batch.result.route.resolvedRoute),
      );
      final result = await _finishSpocBatch(
        backend,
        cache,
        account,
        query,
        online,
        batch.state,
      );
      _validate();
      return FeatureReadBatch(result, finished: batch.finished);
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  }
}

Future<FeatureResult> _finishSpocBatch(
  BridgeContext backend,
  BridgeOfflineCache? cache,
  LocalAccount? account,
  FeatureQuery query,
  FeatureResult online,
  BridgeHomeRefreshState state,
) async {
  if (cache != null && account != null) {
    return bridgeFinishHomeRefresh(
      backend,
      cache,
      account,
      FeatureId.spoc,
      query,
      online,
      state,
    );
  }
  final evidence = account == null
      ? null
      : DataEvidence(
          accountId: account.id,
          origin: DataOrigin.online,
          fetchedAt: bridgeCacheTime(state.fetchedAt.toInt()),
          complete: state.complete,
          savedForOffline: false,
        );
  return online.isEmpty && state.complete
      ? FeatureResult.empty(
          overview: online.overview,
          resolvedRoute: online.resolvedRoute,
          evidence: evidence,
        )
      : FeatureResult.success(
          summary: state.complete ? online.summary : '部分内容尚未更新完成',
          details: online.details,
          overview: online.overview,
          resolvedRoute: online.resolvedRoute,
          evidence: evidence,
        );
}
