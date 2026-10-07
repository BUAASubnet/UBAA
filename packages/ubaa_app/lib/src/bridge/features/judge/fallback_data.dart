part of 'projection.dart';

bool bridgeCanReadJudgeWithoutStorage(BackendException error) =>
    !error.accountMismatch &&
    error.code == UbaaErrorCode.internalError &&
    switch (error.cacheFailure) {
      CacheMaintenanceFailure.corrupt ||
      CacheMaintenanceFailure.unavailable ||
      CacheMaintenanceFailure.unsupportedVersion ||
      CacheMaintenanceFailure.capacity => true,
      _ => false,
    };

// 交回调度器保留现有内容，认证/写入/用户主动查询可先行。
const bridgeJudgeStorageTransition = FeatureReadBatch(
  FeatureResult.success(summary: '在线读取中，离线保存稍后重试'),
  finished: false,
  publish: false,
);
