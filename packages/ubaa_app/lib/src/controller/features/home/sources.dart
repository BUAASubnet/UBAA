import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../../state/models.dart' show HomeSupplementCache, HomeSupplementEntry;
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase;

mixin ControllerHomeSources on ControllerState {
  @internal
  Future<FeatureResult> internalLoadHomeSupplement(
    HomeSupplement source, {
    required bool forceRefresh,
  }) {
    if (internalDisposed ||
        internalReadTransitionBlocked ||
        internalLegacyReadSessionBlocked) {
      return Future.value(internalAcademicTermsConflict());
    }
    if (internalPhase != AppPhase.home) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired),
        ),
      );
    }
    final backend = internalBackend;
    if (backend is! FeatureQueryBackend) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported),
        ),
      );
    }
    var cache = internalHomeSupplementCache;
    if (cache == null ||
        !identical(cache.backend, backend) ||
        cache.lifecycle != internalLifecycleEpoch ||
        cache.epoch != internalReadCacheEpoch) {
      cache = HomeSupplementCache(
        backend,
        internalLifecycleEpoch,
        internalReadCacheEpoch,
      );
      internalHomeSupplementCache = cache;
    }
    final previous = cache.entries[source];
    if (previous != null && (previous.pending || !forceRefresh)) {
      return previous.completer.future;
    }
    final entry = HomeSupplementEntry();
    cache.entries[source] = entry;
    unawaited(
      internalFetchHomeSupplement(
        cache,
        entry,
        source,
        backend as FeatureQueryBackend,
        forceRefresh: forceRefresh,
      ),
    );
    return entry.completer.future;
  }

  @internal
  Future<void> internalFetchHomeSupplement(
    HomeSupplementCache cache,
    HomeSupplementEntry entry,
    HomeSupplement source,
    FeatureQueryBackend backend, {
    required bool forceRefresh,
  }) async {
    bool current() =>
        !internalDisposed &&
        internalPhase == AppPhase.home &&
        identical(internalBackend, cache.backend) &&
        identical(internalHomeSupplementCache, cache) &&
        cache.lifecycle == internalLifecycleEpoch &&
        cache.epoch == internalReadCacheEpoch &&
        identical(cache.entries[source], entry);
    final feature = switch (source) {
      HomeSupplement.bykcChosen => FeatureId.bykc,
      HomeSupplement.cgyyOrders => FeatureId.cgyy,
      HomeSupplement.currentWeek => FeatureId.schedule,
    };
    try {
      FeatureResult result;
      if (source == HomeSupplement.currentWeek) {
        final terms = await internalLoadAcademicTerms(
          forceRefresh: forceRefresh,
          priority: ReadPriority.home,
        );
        if (!current()) {
          entry.completer.complete(internalAcademicTermsConflict());
          return;
        }
        if (terms.error != null) {
          entry.completer.complete(terms);
          return;
        }
        final selected = terms.details
            .map((d) => d.presentation)
            .whereType<TermPresentation>()
            .where((t) => t.selected && t.code.trim().isNotEmpty)
            .toList();
        if (selected.length != 1) {
          entry.completer.complete(
            FeatureResult.empty(resolvedRoute: terms.resolvedRoute),
          );
          return;
        }
        final term = selected.single.code;
        result = await internalScheduleAuxiliaryRead(
          cache.backend,
          feature,
          ReadPriority.home,
          current,
          () => backend.loadFeatureQuery(
            FeatureId.schedule,
            FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
          ),
        );
        if (result.error == null) {
          final weeks = result.details.where((d) {
            final p = d.presentation;
            return p is WeekPresentation &&
                p.current &&
                p.number > 0 &&
                p.requestTerm == term &&
                p.responseTerm == term;
          }).toList();
          result = weeks.length == 1
              ? FeatureResult.success(
                  details: List.unmodifiable(weeks),
                  resolvedRoute: result.resolvedRoute,
                )
              : FeatureResult.empty(resolvedRoute: result.resolvedRoute);
        }
      } else {
        result = await internalScheduleAuxiliaryRead(
          cache.backend,
          feature,
          ReadPriority.home,
          current,
          () => backend.loadFeatureQuery(
            feature,
            FeatureQuery(
              view: source == HomeSupplement.bykcChosen
                  ? FeatureQueryView.bykcChosenCourses
                  : FeatureQueryView.cgyyOrders,
            ),
          ),
        );
      }
      if (!current()) {
        entry.completer.complete(internalAcademicTermsConflict());
        return;
      }
      if (result.error case final error?) {
        entry.completer.complete(
          FeatureResult.failure(
            internalRecordFailure(
              error,
              DiagnosticOperation.read,
              feature: feature,
            ),
          ),
        );
      } else {
        entry.completer.complete(
          result.isEmpty
              ? FeatureResult.empty(
                  resolvedRoute: result.resolvedRoute,
                  pagination: result.pagination,
                  overview: result.overview,
                  evidence: result.evidence,
                )
              : FeatureResult.success(
                  summary: result.summary,
                  overview: result.overview,
                  evidence: result.evidence,
                  details: List.unmodifiable(result.details),
                  resolvedRoute: result.resolvedRoute,
                  pagination: result.pagination,
                ),
        );
      }
    } on Object catch (error, stackTrace) {
      entry.completer.complete(
        current()
            ? FeatureResult.failure(
                internalRecordFailure(
                  error,
                  DiagnosticOperation.read,
                  feature: feature,
                  stackTrace: stackTrace,
                ),
              )
            : internalAcademicTermsConflict(),
      );
    } finally {
      entry.pending = false;
    }
  }

  @internal
  bool internalIsHomeDefaultCurrent(
    FeatureId feature,
    int generation,
    int lifecycle,
  ) =>
      !internalDisposed &&
      internalLifecycleEpoch == lifecycle &&
      internalHomeDefaults[feature]?.readContext?.requestRevision == generation;

  @internal
  void internalBeginHomeDefault(FeatureId feature, FeatureReadContext context) {
    internalHomeDefaults[feature] = internalHomeDefaults[feature]!.copyWith(
      status: FeatureLoadStatus.loading,
      readContext: context,
      clearError: true,
    );
  }

  @internal
  void internalAcceptHomeDefault(
    FeatureId feature,
    FeatureResult result,
    FeatureReadContext? context,
  ) {
    final previous = internalHomeDefaults[feature]!;
    final error = result.error;
    final transient =
        error?.code == UbaaErrorCode.networkError ||
        error?.code == UbaaErrorCode.timeout ||
        error?.code == UbaaErrorCode.upstreamUnavailable;
    if (error != null &&
        result.evidence == null &&
        result.details.isEmpty &&
        result.overview == null &&
        ((previous.evidence != null) ||
            (transient &&
                previous.updatedAt != null &&
                (previous.details.isNotEmpty || previous.overview != null)))) {
      internalHomeDefaults[feature] = previous.copyWith(
        status: FeatureLoadStatus.stale,
        error: error,
        readContext: context,
      );
      return;
    }
    internalHomeDefaults[feature] = FeatureSnapshot(
      feature: feature,
      status: error != null
          ? (result.evidence != null ||
                    result.details.isNotEmpty ||
                    result.overview != null
                ? FeatureLoadStatus.stale
                : FeatureLoadStatus.failure)
          : result.evidence?.complete == false
          ? FeatureLoadStatus.stale
          : result.isEmpty
          ? FeatureLoadStatus.empty
          : FeatureLoadStatus.success,
      summary: result.summary,
      overview: result.overview,
      details: result.details,
      error: error,
      resolvedRoute: result.resolvedRoute,
      pagination: result.pagination,
      updatedAt: result.evidence?.fetchedAt ?? DateTime.now(),
      evidence: result.evidence,
      readContext: context,
    );
  }
}
