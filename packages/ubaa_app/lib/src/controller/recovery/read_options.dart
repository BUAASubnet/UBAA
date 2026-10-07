import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/offline.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase;

mixin ControllerLocalReadOptions on ControllerState {
  @internal
  Future<FeatureResult> internalLocalFirstOptions(
    FeatureQuery query,
    bool forceRefresh,
    Future<FeatureResult> Function() read, {
    FeatureId feature = FeatureId.schedule,
  }) {
    if (internalClearingBusinessCache)
      return Future.value(internalAcademicTermsConflict());
    final online = read();
    if (forceRefresh ||
        internalBackend is! OfflineQueryBackend ||
        internalLocalAccount == null)
      return online;
    final backend = internalBackend;
    final account = internalLocalAccount!;
    final lifecycle = internalLifecycleEpoch, epoch = internalReadCacheEpoch;
    final policy = internalLoginForm.routePolicy;
    bool current() =>
        !internalDisposed &&
        !internalIsSigningOut &&
        internalPhase == AppPhase.home &&
        identical(backend, internalBackend) &&
        lifecycle == internalLifecycleEpoch &&
        epoch == internalReadCacheEpoch &&
        internalLocalAccount?.id == account.id &&
        policy == internalLoginForm.routePolicy;
    Future<FeatureResult?> localRead() async {
      try {
        await internalOfflineOpenFuture;
        if (!current()) return null;
        final read = await (backend as OfflineQueryBackend).readCachedQuery(
          feature,
          query,
          policy,
        );
        if (!current()) return null;
        if (read.error != null)
          internalLocalCacheError = internalRecordFailure(
            read.error!,
            DiagnosticOperation.read,
            feature: feature,
          );
        final value = read.projection;
        if (value == null ||
            value.accountId != account.id ||
            value.feature != feature ||
            !value.readContext.hasSameQuery(query) ||
            (policy == RoutePolicy.direct &&
                value.route != ConnectionMode.direct) ||
            (policy == RoutePolicy.webvpn &&
                value.route != ConnectionMode.webvpn))
          return null;
        final snapshot = value.toSnapshot();
        return snapshot.details.isEmpty
            ? FeatureResult.empty(
                resolvedRoute: snapshot.resolvedRoute,
                evidence: snapshot.evidence,
              )
            : FeatureResult.success(
                details: snapshot.details,
                resolvedRoute: snapshot.resolvedRoute,
                evidence: snapshot.evidence,
              );
      } on Object catch (error, stackTrace) {
        if (current())
          internalLocalCacheError = internalRecordFailure(
            error,
            DiagnosticOperation.read,
            feature: feature,
            stackTrace: stackTrace,
          );
        return null;
      }
    }

    final local = localRead();
    // 在线任务继续更新原内存与持久范围；只读选项不需要等它完成。
    return Future.any([
      local.then((value) => value ?? online),
      online.then(
        (value) async => value.error == null ? value : await local ?? value,
      ),
    ]);
  }
}
