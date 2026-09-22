part of '../../bridge_backend.dart';

Future<FeatureReadTask> _beginSpocDetailRead(
  BridgeBackend backend,
  BridgeOfflineCache? cache,
  LocalAccount? account,
  FeatureQuery query,
  int generation,
) async {
  final id = _requiredQueryValue(query.assignmentId, '作业编号');
  try {
    final task = cache == null
        ? await backend.client.beginSpocDetailOnline(
            expectedIdentity: account?.username,
            assignmentId: id,
          )
        : await backend.client.beginSpocDetailScan(
            cache: cache,
            assignmentId: id,
          );
    try {
      _checkOfflineGeneration(backend, generation);
    } catch (_) {
      task.cancel();
      rethrow;
    }
    return _SpocDetailTask(backend, cache, account, query, task, generation);
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

final class _SpocDetailTask implements FeatureReadTask {
  _SpocDetailTask(
    this.backend,
    this.cache,
    this.account,
    this.query,
    this.task,
    this.generation,
  );
  final BridgeBackend backend;
  final BridgeOfflineCache? cache;
  final LocalAccount? account;
  final FeatureQuery query;
  final BridgeSpocDetailScan task;
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
      final batch = await backend.client.nextSpocDetailScan(task: task);
      _validate();
      final value = batch.result;
      if (value == null) {
        if (batch.finished)
          throw const BackendException(UbaaErrorCode.upstreamChanged);
        return const FeatureReadBatch(
          FeatureResult.success(summary: '正在核实当前作业'),
          finished: false,
          publish: false,
        );
      }
      if (!batch.finished || value.data.assignmentId != query.assignmentId) {
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      }
      final result = await _finishSpocBatch(
        backend,
        cache,
        account,
        query,
        _mapSpocHomeDetail(
          value.data,
          _toConnectionMode(value.route.resolvedRoute),
        ),
        batch.state,
      );
      _validate();
      return FeatureReadBatch(result, finished: true);
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }
}
