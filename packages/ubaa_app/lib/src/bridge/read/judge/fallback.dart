part of '../../bridge_backend.dart';

bool _canReadJudgeWithoutStorage(BackendException error) =>
    !error.accountMismatch &&
    error.code == UbaaErrorCode.internalError &&
    switch (error.cacheFailure) {
      CacheMaintenanceFailure.corrupt ||
      CacheMaintenanceFailure.unavailable ||
      CacheMaintenanceFailure.unsupportedVersion ||
      CacheMaintenanceFailure.capacity => true,
      _ => false,
    };

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
  final BridgeBackend backend;
  final LocalAccount account;
  final FeatureQuery query;
  final int generation;
  FeatureReadTask? delegate;
  CacheMaintenanceFailure? cacheFailure;
  bool _cancelled = false;
  bool _online = false;

  void _validate() {
    _checkOfflineGeneration(backend, generation);
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
      return _judgeStorageTransition;
    }
    try {
      final batch = await delegate!.next();
      _validate();
      return batch;
    } on BackendException catch (error) {
      _validate();
      if (_online || !_canReadJudgeWithoutStorage(error)) rethrow;
      delegate!.cancel();
      delegate = null;
      cacheFailure = error.cacheFailure;
      return _judgeStorageTransition;
    }
  }
}

// 交回调度器保留现有内容，认证/写入/用户主动查询可先行。
const _judgeStorageTransition = FeatureReadBatch(
  FeatureResult.success(summary: '本机缓存暂不可用，继续在线读取'),
  finished: false,
  publish: false,
);
