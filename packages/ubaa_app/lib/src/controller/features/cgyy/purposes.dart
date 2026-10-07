import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../../state/models.dart' show CgyyPurposeCache;
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase;

mixin ControllerCgyyPurposes on ControllerState {
  @internal
  bool internalPurposesCurrent(CgyyPurposeCache cache) =>
      !internalDisposed &&
      internalPhase == AppPhase.home &&
      identical(internalReadCaches.purposes, cache) &&
      identical(cache.backend, internalBackend) &&
      cache.lifecycle == internalLifecycleEpoch &&
      cache.epoch == internalReadCacheEpoch;

  @internal
  Future<FeatureResult> internalLoadCgyyPurposes({required bool forceRefresh}) {
    final UbaaErrorCode? error =
        internalDisposed ||
            internalReadTransitionBlocked ||
            internalLegacyReadSessionBlocked
        ? UbaaErrorCode.operationConflict
        : internalPhase != AppPhase.home
        ? UbaaErrorCode.authenticationRequired
        : internalBackend is! FeatureQueryBackend
        ? UbaaErrorCode.unsupported
        : null;
    if (error != null)
      return Future.value(
        FeatureResult.failure(UbaaErrorMapper.fromCode(error)),
      );
    final previous = internalReadCaches.purposes;
    if (previous != null &&
        internalPurposesCurrent(previous) &&
        (previous.pending || !forceRefresh)) {
      return previous.completer.future;
    }
    final cache = CgyyPurposeCache(
      internalBackend,
      internalLifecycleEpoch,
      internalReadCacheEpoch,
    );
    internalReadCaches.purposes = cache;
    unawaited(internalFetchCgyyPurposes(cache));
    return cache.completer.future;
  }

  @internal
  Future<void> internalFetchCgyyPurposes(CgyyPurposeCache cache) async {
    FeatureResult result;
    try {
      result = await internalScheduleAuxiliaryRead(
        cache.backend,
        FeatureId.cgyy,
        ReadPriority.interactive,
        () => internalPurposesCurrent(cache),
        () => (cache.backend as FeatureQueryBackend).loadFeatureQuery(
          FeatureId.cgyy,
          const FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes),
        ),
      );
      if (!internalPurposesCurrent(cache)) {
        result = FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
        );
      } else if (result.error case final error?) {
        result = FeatureResult.failure(
          internalRecordFailure(
            error,
            DiagnosticOperation.read,
            feature: FeatureId.cgyy,
          ),
        );
      } else {
        result = result.isEmpty
            ? FeatureResult.empty(
                resolvedRoute: result.resolvedRoute,
                evidence: result.evidence,
              )
            : FeatureResult.success(
                summary: result.summary,
                evidence: result.evidence,
                resolvedRoute: result.resolvedRoute,
                details: List.unmodifiable(
                  result.details.map(
                    (detail) => FeatureDetail(
                      title: detail.title,
                      subtitle: detail.subtitle,
                      fields: List.unmodifiable(detail.fields),
                      presentation: detail.presentation,
                    ),
                  ),
                ),
              );
      }
    } on Object catch (error, stackTrace) {
      result = FeatureResult.failure(
        internalPurposesCurrent(cache)
            ? internalRecordFailure(
                error,
                DiagnosticOperation.read,
                stackTrace: stackTrace,
                feature: FeatureId.cgyy,
              )
            : UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
      );
    }
    cache.pending = false;
    if (result.error != null && identical(internalReadCaches.purposes, cache))
      internalReadCaches.purposes = null;
    cache.completer.complete(result);
  }
}
