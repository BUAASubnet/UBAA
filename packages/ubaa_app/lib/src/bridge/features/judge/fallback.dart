part of 'reader.dart';

/// 本地失败后在下一调度批次建立在线计划；旧计划永不继续。
final class _JudgeFallbackTask implements FeatureReadTask {
  _JudgeFallbackTask(
    this.backend,
    this.account,
    this.query,
    this.generation, {
    this.delegate,
    this.cacheFailure,
  });
  final BridgeContext backend;
  final LocalAccount account;
  final FeatureQuery query;
  final int generation;
  FeatureReadTask? delegate;
  CacheMaintenanceFailure? cacheFailure;
  bool _cancelled = false;
  bool _online = false;

  void _validate() {
    bridgeCheckOfflineGeneration(backend, generation);
    if (_cancelled)
      throw const BackendException(UbaaErrorCode.operationConflict);
  }

  @override
  void cancel() {
    _cancelled = true;
    delegate?.cancel();
  }

  @override
  Future<FeatureReadBatch> next() async {
    _validate();
    if (delegate == null) {
      FeatureReadTask? replacement;
      try {
        replacement = await _beginOnlineJudgeRead(
          backend,
          account,
          query,
          cacheFailure: cacheFailure,
        );
        _validate();
      } catch (_) {
        replacement?.cancel();
        _validate();
        rethrow;
      }
      delegate = replacement;
      _online = true;
      return bridgeJudgeStorageTransition;
    }
    try {
      final batch = await delegate!.next();
      _validate();
      return batch;
    } on BackendException catch (error) {
      _validate();
      if (_online || !bridgeCanReadJudgeWithoutStorage(error)) rethrow;
      delegate!.cancel();
      delegate = null;
      cacheFailure = error.cacheFailure;
      return bridgeJudgeStorageTransition;
    }
  }
}
