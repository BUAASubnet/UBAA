import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/offline.dart';
import '../state/state.dart' show ControllerState;

mixin ControllerOfflineQuery on ControllerState {
  @internal
  Future<void> internalRestoreCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    int generation,
    int lifecycle,
    int? ygdkGeneration,
  ) async {
    final backend = internalBackend;
    final account = internalLocalAccount;
    final policy = internalLoginForm.routePolicy;
    if (backend is! OfflineQueryBackend || account == null) return;
    bool current() =>
        identical(internalBackend, backend) &&
        internalLocalAccount?.id == account.id &&
        internalLoginForm.routePolicy == policy &&
        internalIsFeatureLoadCurrent(
          feature,
          generation,
          lifecycle,
          ygdkGeneration,
        );
    try {
      await internalOfflineOpenFuture;
      if (!current()) return;
      final read = await (backend as OfflineQueryBackend).readCachedQuery(
        feature,
        query,
        policy,
      );
      if (!current()) return;
      final projection = read.projection;
      final previous = internalSnapshots[feature]!;
      if (projection != null &&
          projection.accountId == account.id &&
          projection.feature == feature &&
          projection.readContext.hasSameQuery(query) &&
          (policy == RoutePolicy.auto ||
              (policy == RoutePolicy.direct &&
                  projection.route == ConnectionMode.direct) ||
              (policy == RoutePolicy.webvpn &&
                  projection.route == ConnectionMode.webvpn)) &&
          (previous.evidence == null ||
              previous.evidence!.origin == DataOrigin.persisted) &&
          previous.status != FeatureLoadStatus.success &&
          previous.status != FeatureLoadStatus.empty) {
        internalSnapshots[feature] = projection.toSnapshot().copyWith(
          readContext: previous.readContext,
          status: previous.status == FeatureLoadStatus.loading
              ? FeatureLoadStatus.loading
              : FeatureLoadStatus.stale,
          error: previous.error,
        );
      }
      if (read.error != null)
        internalLocalCacheError = internalRecordFailure(
          read.error!,
          DiagnosticOperation.read,
          feature: feature,
        );
      internalNotify();
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      internalLocalCacheError = internalRecordFailure(
        error,
        DiagnosticOperation.read,
        feature: feature,
        stackTrace: stackTrace,
      );
      internalNotify();
    }
  }
}
