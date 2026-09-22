part of '../../bridge_backend.dart';

Future<FeatureReadTask?> _beginProgressiveRead(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery? query, {
  LocalAccount? expectedAccount,
}) => feature == FeatureId.spoc
    ? _beginSpocRead(backend, query, expectedAccount: expectedAccount)
    : _beginJudgeRead(
        backend,
        feature,
        query,
        expectedAccount: expectedAccount,
      );

Future<FeatureReadTask?> _beginSpocRead(
  BridgeBackend backend,
  FeatureQuery? query, {
  LocalAccount? expectedAccount,
}) async {
  final selected = query ?? const FeatureQuery();
  if (selected.view != FeatureQueryView.summary) return null;
  await _awaitOfflineScope(backend);
  final generation = backend._offlineGeneration;
  final account = expectedAccount ?? backend._offlineAccount;
  final cache = account != null && account.id == backend._offlineAccount?.id
      ? backend._offlineCache
      : null;
  try {
    final task = cache == null
        ? await backend.client.beginSpocOnline(
            expectedIdentity: account?.username,
          )
        : await backend.client.beginSpocScan(cache: cache);
    try {
      _checkOfflineGeneration(backend, generation);
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
    throw _mapError(error);
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
  final BridgeBackend backend;
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
    _checkOfflineGeneration(backend, generation);
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
      final online = _mapSpocHome(
        batch.result.data,
        _toConnectionMode(batch.result.route.resolvedRoute),
      );
      FeatureResult result;
      if (cache != null && account != null) {
        result = await _finishHomeRefresh(
          backend,
          cache,
          account,
          FeatureId.spoc,
          query,
          online,
          batch.state,
        );
      } else {
        final evidence = account == null
            ? null
            : DataEvidence(
                accountId: account!.id,
                origin: DataOrigin.online,
                fetchedAt: _cacheTime(batch.state.fetchedAt.toInt()),
                complete: batch.state.complete,
                savedForOffline: false,
              );
        result = online.isEmpty && batch.state.complete
            ? FeatureResult.empty(
                overview: online.overview,
                resolvedRoute: online.resolvedRoute,
                evidence: evidence,
              )
            : FeatureResult.success(
                summary: batch.state.complete ? online.summary : '部分内容尚未更新完成',
                details: online.details,
                overview: online.overview,
                resolvedRoute: online.resolvedRoute,
                evidence: evidence,
              );
      }
      _validate();
      return FeatureReadBatch(result, finished: batch.finished);
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }
}
