import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../../state/models.dart' show AcademicWeekEntry, AcademicWeeksCache;
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase;

mixin ControllerAcademicWeeks on ControllerState {
  @internal
  UiError? internalWeeksGuard() {
    if (internalDisposed ||
        internalReadTransitionBlocked ||
        internalLegacyReadSessionBlocked) {
      return UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
    }
    if (internalPhase != AppPhase.home) {
      return UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired);
    }
    if (internalBackend is! FeatureQueryBackend) {
      return UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported);
    }
    return null;
  }

  @internal
  bool internalWeeksCurrent(AcademicWeeksCache cache) =>
      internalWeeksGuard() == null &&
      identical(internalAcademicWeeksCache, cache) &&
      identical(cache.backend, internalBackend) &&
      cache.lifecycle == internalLifecycleEpoch &&
      cache.epoch == internalReadCacheEpoch;

  @internal
  Future<FeatureResult> internalLoadAcademicWeeks(
    String term, {
    required bool forceRefresh,
  }) {
    if (internalWeeksGuard() case final error?)
      return Future.value(FeatureResult.failure(error));
    if (term.trim().isEmpty) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput),
        ),
      );
    }
    final previous = internalAcademicWeeksCache;
    final cache = previous != null && internalWeeksCurrent(previous)
        ? previous
        : internalAcademicWeeksCache = AcademicWeeksCache(
            internalBackend,
            internalLifecycleEpoch,
            internalReadCacheEpoch,
          );
    final existing = cache.entries[term];
    if (existing != null && (existing.pending || !forceRefresh))
      return existing.completer.future;
    final entry = AcademicWeekEntry();
    cache.entries[term] = entry;
    unawaited(internalFetchAcademicWeeks(cache, entry, term));
    return entry.completer.future;
  }

  @internal
  Future<void> internalFetchAcademicWeeks(
    AcademicWeeksCache cache,
    AcademicWeekEntry entry,
    String term,
  ) async {
    FeatureResult result;
    try {
      // 先登记entry再调用backend，同步抛错也不会留下悬空在途状态。
      result = await internalScheduleAuxiliaryRead(
        cache.backend,
        FeatureId.schedule,
        ReadPriority.interactive,
        () => internalWeeksCurrent(cache),
        () => (cache.backend as FeatureQueryBackend).loadFeatureQuery(
          FeatureId.schedule,
          FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
        ),
      );
      if (!internalWeeksCurrent(cache)) {
        result = internalAcademicTermsConflict();
      } else if (result.error case final error?) {
        result = FeatureResult.failure(
          internalRecordFailure(
            error,
            DiagnosticOperation.read,
            feature: FeatureId.schedule,
          ),
        );
      } else {
        result = result.isEmpty
            ? FeatureResult.empty(
                resolvedRoute: result.resolvedRoute,
                pagination: result.pagination,
              )
            : FeatureResult.success(
                summary: result.summary,
                resolvedRoute: result.resolvedRoute,
                pagination: result.pagination,
                details: List.unmodifiable(
                  result.details.map((detail) {
                    final navigation = detail.readNavigation;
                    return FeatureDetail(
                      title: detail.title,
                      subtitle: detail.subtitle,
                      fields: List.unmodifiable(detail.fields),
                      actions: List.unmodifiable(detail.actions),
                      presentation: detail.presentation,
                      readNavigation: navigation == null
                          ? null
                          : FeatureReadNavigation(
                              feature: navigation.feature,
                              query: navigation.query.copyWith(
                                judgeKeys: List.unmodifiable(
                                  navigation.query.judgeKeys,
                                ),
                              ),
                            ),
                    );
                  }),
                ),
              );
      }
    } on Object catch (error, stackTrace) {
      result = !internalWeeksCurrent(cache)
          ? internalAcademicTermsConflict()
          : FeatureResult.failure(
              internalRecordFailure(
                error,
                DiagnosticOperation.read,
                stackTrace: stackTrace,
                feature: FeatureId.schedule,
              ),
            );
    }
    entry.pending = false;
    // 旧cache对象的完成只清理自身；不能触及新登录/路线代次的在途请求。
    if (result.error != null && identical(cache.entries[term], entry))
      cache.entries.remove(term);
    entry.completer.complete(result);
  }
}
