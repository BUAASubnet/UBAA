import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/cache_management.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase;

mixin ControllerCacheManagement on ControllerState {
  @internal
  bool internalCacheOwnerCurrent(
    String accountId,
    UbaaBackend backend,
    int epoch,
  ) =>
      !internalDisposed &&
      !internalIsSigningOut &&
      internalPhase == AppPhase.home &&
      internalLocalAccount?.id == accountId &&
      identical(internalBackend, backend) &&
      epoch == internalLifecycleEpoch;

  @internal
  void internalCheckCacheManagement(String accountId) {
    if (internalDisposed ||
        internalIsSigningOut ||
        internalPhase != AppPhase.home ||
        internalLocalAccount?.id != accountId ||
        internalClearingBusinessCache ||
        isLoggingIn ||
        internalRebuildingBackend ||
        internalWriteTransitions != 0 ||
        internalActiveRecovery != null ||
        internalWriteCoordinator.hasPendingOperation) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    if (internalBackend is! CacheManagementBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
  }

  @internal
  Future<CacheUsageSummary> internalReadCacheUsage(String accountId) async {
    // 数值读取不需要认证或写资格，只避开本地清理和账号切换。
    if (internalDisposed ||
        cacheAccountId != accountId ||
        internalClearingBusinessCache) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    final backend = internalBackend, epoch = internalLifecycleEpoch;
    await internalOfflineOpenFuture;
    if (!internalCacheOwnerCurrent(accountId, backend, epoch)) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    final value = await (backend as CacheManagementBackend).cacheUsage(
      accountId: accountId,
    );
    if (!internalCacheOwnerCurrent(accountId, backend, epoch) ||
        value.accountId != accountId) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return value;
  }

  @internal
  Future<CacheClearOutcome> internalClearControllerCache(
    String accountId,
  ) async {
    internalCheckCacheManagement(accountId);
    final backend = internalBackend;
    var epoch = internalLifecycleEpoch;
    internalClearingBusinessCache = true;
    internalWriteTransitions++;
    internalCancelDeferredRecovery();
    internalNotify();
    try {
      // 初次保险箱读取可能尚未完成；不能先失效它而使后台从未打开缓存。
      await internalOfflineOpenFuture;
      if (!internalCacheOwnerCurrent(accountId, backend, epoch)) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      epoch = ++internalLifecycleEpoch;
      // 清理移交了仓库所有权，旧首页读取不能按路线切换重试。
      internalOfflineAccountEpoch++;
      internalYgdkGeneration++;
      for (final scope in internalReadScopes.toList()) {
        scope.cancel();
      }
      internalPumpReadTasks();
      final result = await internalClearBackendCache(backend, accountId, epoch);
      if (!internalCacheOwnerCurrent(accountId, backend, epoch)) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      internalClearBusinessProjections();
      internalBusinessCacheEpoch++;
      internalLocalCacheError = result.cacheReady
          ? null
          : UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
      return result;
    } finally {
      if (internalCacheOwnerCurrent(accountId, backend, epoch))
        internalSettleCancelledLoads();
      internalClearingBusinessCache = false;
      internalWriteTransitions--;
      internalNotify();
    }
  }

  @internal
  Future<CacheClearOutcome> internalClearBackendCache(
    UbaaBackend backend,
    String accountId,
    int epoch,
  ) async {
    if (backend is! CacheRecoveryBackend) {
      return (backend as CacheManagementBackend).clearBusinessCache(
        accountId: accountId,
      );
    }
    final store = internalLocalAccountStore, account = internalLocalAccount;
    if (store == null || account == null || account.id != accountId) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    final key = await store.cacheKey(account);
    try {
      if (!internalCacheOwnerCurrent(accountId, backend, epoch)) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      return await (backend as CacheRecoveryBackend)
          .clearOrRebuildBusinessCache(account: account, key: key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  @internal
  void internalClearBusinessProjections() {
    internalClearWriteReadbacks();
    for (final feature in FeatureId.values) {
      internalSnapshots[feature] = FeatureSnapshot(
        feature: feature,
        readContext: internalSnapshots[feature]!.readContext,
      );
      internalHomeDefaults[feature] = FeatureSnapshot(
        feature: feature,
        readContext: internalHomeDefaults[feature]!.readContext,
      );
    }
    internalProfileDisplay = null;
    internalProfileDisplayEpoch = -1;
    internalProfileRefreshedEpoch = -1;
    internalProfileFailureEpoch = -1;
    internalProfileRequest = null;
    internalHomeSupplementCache = null;
    internalGradesReadCache = null;
    internalAcademicWeeksCache = null;
    internalCgyyPurposeCache = null;
    internalAcademicTermsResult = null;
    internalAcademicTermsPending = null;
    internalAcademicTermsSerial++;
    internalYgdkReadbackState = const YgdkReadbackState.empty();
  }

  @internal
  void internalSettleCancelledLoads() {
    for (final snapshots in [internalSnapshots, internalHomeDefaults]) {
      for (final feature in FeatureId.values) {
        final value = snapshots[feature]!;
        if (value.status != FeatureLoadStatus.loading) continue;
        snapshots[feature] = value.copyWith(
          status:
              value.details.isNotEmpty ||
                  value.overview != null ||
                  value.evidence != null
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.idle,
        );
      }
    }
  }
}
