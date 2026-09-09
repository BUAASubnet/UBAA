part of '../app_controller.dart';

final class _AcademicWeeksCache {
  _AcademicWeeksCache(this.backend, this.lifecycle, this.epoch);
  final UbaaBackend backend;
  final int lifecycle, epoch;
  final entries = <String, _AcademicWeekEntry>{};
}

final class _AcademicWeekEntry {
  final completer = Completer<FeatureResult>();
  bool pending = true;
}

extension _AppControllerAcademicWeeks on AppController {
  UiError? _weeksGuard() {
    if (_disposed || _writeTransitions != 0) {
      return UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
    }
    if (_phase != AppPhase.home) {
      return UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired);
    }
    if (_backend is! FeatureQueryBackend) {
      return UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported);
    }
    return null;
  }

  bool _weeksCurrent(_AcademicWeeksCache cache) =>
      _weeksGuard() == null &&
      identical(_academicWeeksCache, cache) &&
      identical(cache.backend, _backend) &&
      cache.lifecycle == _lifecycleEpoch &&
      cache.epoch == _readCacheEpoch;

  Future<FeatureResult> _loadAcademicWeeks(
    String term, {
    required bool forceRefresh,
  }) {
    if (_weeksGuard() case final error?)
      return Future.value(FeatureResult.failure(error));
    if (term.trim().isEmpty) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput),
        ),
      );
    }
    final previous = _academicWeeksCache;
    final cache = previous != null && _weeksCurrent(previous)
        ? previous
        : _academicWeeksCache = _AcademicWeeksCache(
            _backend,
            _lifecycleEpoch,
            _readCacheEpoch,
          );
    final existing = cache.entries[term];
    if (existing != null && (existing.pending || !forceRefresh))
      return existing.completer.future;
    final entry = _AcademicWeekEntry();
    cache.entries[term] = entry;
    unawaited(_fetchAcademicWeeks(cache, entry, term));
    return entry.completer.future;
  }

  Future<void> _fetchAcademicWeeks(
    _AcademicWeeksCache cache,
    _AcademicWeekEntry entry,
    String term,
  ) async {
    FeatureResult result;
    try {
      // 先登记entry再调用backend，同步抛错也不会留下悬空在途状态。
      result = await (cache.backend as FeatureQueryBackend).loadFeatureQuery(
        FeatureId.schedule,
        FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
      );
      if (!_weeksCurrent(cache)) {
        result = _academicTermsConflict();
      } else if (result.error case final error?) {
        result = FeatureResult.failure(
          _recordFailure(
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
      result = !_weeksCurrent(cache)
          ? _academicTermsConflict()
          : FeatureResult.failure(
              _recordFailure(
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
