import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/offline.dart';
import '../state/models.dart' show controllerHomeDefaultFeatures;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerOfflineCache on ControllerState {
  @internal
  Future<void> internalRestoreCachedHome(LocalAccount account) async {
    final backend = internalBackend;
    if (backend is! OfflineCacheBackend) return;
    final offline = backend as OfflineCacheBackend;
    final accountEpoch = ++internalOfflineAccountEpoch;
    final opened = Completer<void>();
    internalOfflineOpenFuture = opened.future;
    bool current() =>
        !internalDisposed &&
        !internalIsSigningOut &&
        !internalRebuildingBackend &&
        accountEpoch == internalOfflineAccountEpoch &&
        identical(backend, internalBackend) &&
        internalLocalAccount?.id == account.id &&
        (internalPhase == AppPhase.home || internalPhase == AppPhase.loggingIn);
    try {
      final key = await internalLocalAccountStore!.cacheKey(account);
      try {
        if (!current()) return;
        await offline.openOfflineAccount(account, key);
        opened.complete();
      } finally {
        key.fillRange(0, key.length, 0);
      }
      if (!current()) return;
      unawaited(internalLoadWriteReadbacks());
      final profileEpoch = internalLifecycleEpoch;
      unawaited(internalRestoreCachedProfile(backend, account, profileEpoch));
      final read = await internalReadCurrentCachedHome(offline, current);
      if (read == null || !current()) return;
      final (projections, policy, readEpoch) = read;
      if (readEpoch != internalLifecycleEpoch ||
          policy != internalLoginForm.routePolicy)
        return;
      if (readEpoch != profileEpoch)
        unawaited(internalRestoreCachedProfile(backend, account, readEpoch));
      for (final projection in projections) {
        final supplement =
            (projection.feature == FeatureId.bykc &&
                projection.readContext.query?.view ==
                    FeatureQueryView.bykcChosenCourses) ||
            (projection.feature == FeatureId.cgyy &&
                projection.readContext.query?.view ==
                    FeatureQueryView.cgyyOrders);
        if (projection.accountId != account.id ||
            (policy == RoutePolicy.direct &&
                projection.route != ConnectionMode.direct) ||
            (policy == RoutePolicy.webvpn &&
                projection.route != ConnectionMode.webvpn) ||
            (!controllerHomeDefaultFeatures.contains(projection.feature) &&
                !supplement))
          continue;
        final previous = internalHomeDefaults[projection.feature]!;
        // 磁盘慢于网络时不能倒退；当前查询面板不接收首页默认查询的数据。
        if ((previous.evidence != null &&
                previous.evidence!.origin != DataOrigin.persisted) ||
            previous.status == FeatureLoadStatus.success ||
            previous.status == FeatureLoadStatus.empty)
          continue;
        final snapshot = projection.toSnapshot().copyWith(
          readContext: supplement
              ? projection.readContext
              : previous.readContext,
        );
        internalHomeDefaults[projection.feature] = snapshot;
        if (supplement) continue;
        final visible = internalSnapshots[projection.feature]!;
        if (visible.readContext?.query == null &&
            (visible.evidence == null ||
                visible.evidence!.origin == DataOrigin.persisted) &&
            visible.status != FeatureLoadStatus.success &&
            visible.status != FeatureLoadStatus.empty) {
          internalSnapshots[projection.feature] = snapshot.copyWith(
            readContext: visible.readContext,
          );
        }
      }
      internalLocalCacheError = projections.error == null
          ? null
          : internalRecordFailure(
              projections.error!,
              DiagnosticOperation.initialization,
            );
      internalNotify();
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      internalLocalCacheError = internalRecordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      internalNotify();
    } finally {
      if (!opened.isCompleted) opened.complete();
    }
  }

  @internal
  Future<(OfflineHomeRead, RoutePolicy, int)?> internalReadCurrentCachedHome(
    OfflineCacheBackend offline,
    bool Function() ownsAccount,
  ) async {
    // 账号库的打开不从属于某条路线；投影则每次固定路线和页面代次。
    while (ownsAccount()) {
      final epoch = internalLifecycleEpoch,
          policy = internalLoginForm.routePolicy;
      try {
        final result = await offline.readCachedHome(policy);
        if (!ownsAccount()) return null;
        if (epoch != internalLifecycleEpoch ||
            policy != internalLoginForm.routePolicy)
          continue;
        return (result, policy, epoch);
      } on Object {
        if (!ownsAccount()) return null;
        if (epoch != internalLifecycleEpoch ||
            policy != internalLoginForm.routePolicy)
          continue;
        rethrow;
      }
    }
    return null;
  }

  @internal
  Future<void> internalCloseOfflineAccount({bool remove = false}) async {
    internalOfflineAccountEpoch++;
    final backend = internalBackend;
    if (backend is OfflineCacheBackend) {
      final offline = backend as OfflineCacheBackend;
      await offline.deactivateOfflineAccount();
      if (remove) await offline.clearOfflineAccount();
    }
    final account = internalLocalAccount;
    if (remove && account != null)
      await internalLocalAccountStore?.removeAccount(account.id);
  }

  @internal
  Future<void> internalRejectMismatchedAccount() async {
    internalLifecycleEpoch++;
    internalReadCacheEpoch++;
    internalUser = null;
    internalActiveRoutes = const [];
    internalResetFeatureSnapshots();
    internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
    internalSetPhase(AppPhase.login);
    final scope = internalCaptureSessionScope();
    final formRevision = internalLoginCredentialRevision;
    try {
      // 同步入队两个关闭动作，不能在等待安全索引时让新登录先启用缓存。
      await Future.wait<void>([
        internalLocalAccountStore?.signOut() ?? Future<void>.value(),
        internalCloseOfflineAccount(),
      ]);
    } on Object catch (error, stackTrace) {
      if (!scope.isCurrent || formRevision != internalLoginCredentialRevision)
        return;
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.logout,
        stackTrace: stackTrace,
      );
      internalNotify();
    }
  }
}
