part of '../app_controller.dart';

final class _HomeSupplementCache {
  _HomeSupplementCache(this.backend, this.lifecycle, this.epoch);
  final UbaaBackend backend;
  final int lifecycle, epoch;
  final entries = <HomeSupplement, _HomeSupplementEntry>{};
}

final class _HomeSupplementEntry {
  final completer = Completer<FeatureResult>();
  bool pending = true;
}

extension _AppControllerHomeSources on AppController {
  Future<FeatureResult> _loadHomeSupplement(
    HomeSupplement source, {
    required bool forceRefresh,
  }) {
    if (_disposed || _writeTransitions != 0) {
      return Future.value(_academicTermsConflict());
    }
    if (_phase != AppPhase.home) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired),
        ),
      );
    }
    final backend = _backend;
    if (backend is! FeatureQueryBackend) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported),
        ),
      );
    }
    var cache = _homeSupplementCache;
    if (cache == null ||
        !identical(cache.backend, backend) ||
        cache.lifecycle != _lifecycleEpoch ||
        cache.epoch != _readCacheEpoch) {
      cache = _HomeSupplementCache(backend, _lifecycleEpoch, _readCacheEpoch);
      _homeSupplementCache = cache;
    }
    final previous = cache.entries[source];
    if (previous != null && (previous.pending || !forceRefresh)) {
      return previous.completer.future;
    }
    final entry = _HomeSupplementEntry();
    cache.entries[source] = entry;
    unawaited(
      _fetchHomeSupplement(
        cache,
        entry,
        source,
        backend as FeatureQueryBackend,
        forceRefresh: forceRefresh,
      ),
    );
    return entry.completer.future;
  }

  Future<void> _fetchHomeSupplement(
    _HomeSupplementCache cache,
    _HomeSupplementEntry entry,
    HomeSupplement source,
    FeatureQueryBackend backend, {
    required bool forceRefresh,
  }) async {
    bool current() =>
        !_disposed &&
        _phase == AppPhase.home &&
        _writeTransitions == 0 &&
        identical(_backend, cache.backend) &&
        identical(_homeSupplementCache, cache) &&
        cache.lifecycle == _lifecycleEpoch &&
        cache.epoch == _readCacheEpoch &&
        identical(cache.entries[source], entry);
    final feature = switch (source) {
      HomeSupplement.bykcChosen => FeatureId.bykc,
      HomeSupplement.cgyyOrders => FeatureId.cgyy,
      HomeSupplement.currentWeek => FeatureId.schedule,
    };
    try {
      FeatureResult result;
      if (source == HomeSupplement.currentWeek) {
        final terms = await _loadAcademicTerms(forceRefresh: forceRefresh);
        if (!current()) {
          entry.completer.complete(_academicTermsConflict());
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
        result = await backend.loadFeatureQuery(
          FeatureId.schedule,
          FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
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
        result = await backend.loadFeatureQuery(
          feature,
          FeatureQuery(
            view: source == HomeSupplement.bykcChosen
                ? FeatureQueryView.bykcChosenCourses
                : FeatureQueryView.cgyyOrders,
          ),
        );
      }
      if (!current()) {
        entry.completer.complete(_academicTermsConflict());
        return;
      }
      if (result.error case final error?) {
        entry.completer.complete(
          FeatureResult.failure(
            _recordFailure(error, DiagnosticOperation.read, feature: feature),
          ),
        );
      } else {
        entry.completer.complete(
          result.isEmpty
              ? FeatureResult.empty(
                  resolvedRoute: result.resolvedRoute,
                  pagination: result.pagination,
                  overview: result.overview,
                )
              : FeatureResult.success(
                  summary: result.summary,
                  overview: result.overview,
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
                _recordFailure(
                  error,
                  DiagnosticOperation.read,
                  feature: feature,
                  stackTrace: stackTrace,
                ),
              )
            : _academicTermsConflict(),
      );
    } finally {
      entry.pending = false;
    }
  }

  bool _isHomeDefaultCurrent(
    FeatureId feature,
    int generation,
    int lifecycle,
  ) =>
      !_disposed &&
      _lifecycleEpoch == lifecycle &&
      _homeDefaults[feature]?.readContext?.requestRevision == generation;

  void _beginHomeDefault(FeatureId feature, FeatureReadContext context) {
    _homeDefaults[feature] = _homeDefaults[feature]!.copyWith(
      status: FeatureLoadStatus.loading,
      readContext: context,
      clearError: true,
    );
  }

  void _acceptHomeDefault(
    FeatureId feature,
    FeatureResult result,
    FeatureReadContext? context,
  ) {
    final previous = _homeDefaults[feature]!;
    final error = result.error;
    final transient =
        error?.code == UbaaErrorCode.networkError ||
        error?.code == UbaaErrorCode.timeout ||
        error?.code == UbaaErrorCode.upstreamUnavailable;
    if (transient &&
        previous.updatedAt != null &&
        (previous.details.isNotEmpty || previous.overview != null)) {
      _homeDefaults[feature] = previous.copyWith(
        status: FeatureLoadStatus.stale,
        error: error,
        updatedAt: DateTime.now(),
        readContext: context,
      );
      return;
    }
    _homeDefaults[feature] = FeatureSnapshot(
      feature: feature,
      status: error != null
          ? FeatureLoadStatus.failure
          : result.isEmpty
          ? FeatureLoadStatus.empty
          : FeatureLoadStatus.success,
      summary: result.summary,
      overview: result.overview,
      details: result.details,
      error: error,
      resolvedRoute: result.resolvedRoute,
      pagination: result.pagination,
      updatedAt: DateTime.now(),
      readContext: context,
    );
  }
}
