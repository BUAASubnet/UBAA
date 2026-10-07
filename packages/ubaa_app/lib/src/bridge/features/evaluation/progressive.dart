part of 'reader.dart';

Future<FeatureReadTask?> bridgeBeginEvaluationRead(
  BridgeContext backend,
  FeatureQuery? query, {
  LocalAccount? expectedAccount,
}) async {
  final selected = query ?? const FeatureQuery();
  if (!bridgeIsEvaluationCacheQuery(FeatureId.evaluation, selected))
    return null;
  await bridgeAwaitOfflineScope(backend);
  final generation = backend.cache.generation;
  final account = expectedAccount ?? backend.cache.account;
  final cache = account != null && account.id == backend.cache.account?.id
      ? backend.cache.handle
      : null;
  try {
    final task = cache == null
        ? await backend.client.beginEvaluationOnline(
            expectedIdentity: account?.username,
          )
        : await backend.client.beginEvaluationScan(cache: cache);
    try {
      bridgeCheckOfflineGeneration(backend, generation);
    } catch (_) {
      task.cancel();
      rethrow;
    }
    return _EvaluationFeatureTask(
      backend,
      cache,
      account,
      selected,
      task,
      generation,
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

final class _EvaluationFeatureTask implements FeatureReadTask {
  _EvaluationFeatureTask(
    this.backend,
    this.cache,
    this.account,
    this.query,
    this.task,
    this.generation,
  );
  final BridgeContext backend;
  final BridgeOfflineCache? cache;
  final LocalAccount? account;
  final FeatureQuery query;
  final BridgeEvaluationScan task;
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
      final batch = await backend.client.nextEvaluationScan(task: task);
      _validate();
      if (!batch.finished && batch.completedCourseLists == 0) {
        return const FeatureReadBatch(
          FeatureResult.success(summary: '正在核实评教任务'),
          finished: false,
          publish: false,
        );
      }
      var result = await _finishEvaluationRefresh(
        backend,
        cache,
        account,
        query,
        batch.refresh,
      );
      if (batch.error case final error?) {
        result = FeatureResult.partial(
          error: UbaaErrorMapper.fromObject(bridgeMapError(error)),
          summary: result.summary,
          details: result.details,
          overview: result.overview,
          resolvedRoute: result.resolvedRoute,
          evidence: result.evidence,
        );
      }
      _validate();
      return FeatureReadBatch(result, finished: batch.finished);
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  }
}
