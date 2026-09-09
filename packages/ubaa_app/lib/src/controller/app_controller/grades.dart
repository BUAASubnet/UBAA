part of '../app_controller.dart';

final class _GradesReadCache {
  _GradesReadCache(this.backend, this.lifecycle, this.epoch);
  final UbaaBackend backend;
  final int lifecycle, epoch;
  final entries = <String, _GradeReadEntry>{};
  Future<GradesAggregate>? aggregatePending;
  UiError? authenticationError;
}

final class _GradeReadEntry {
  final completer = Completer<FeatureResult>();
  bool pending = true;
  bool freshForAggregate = false;
  FeatureResult? result;
}

extension _AppControllerGrades on AppController {
  Future<GradeTermRead?> _loadCurrentGrades({
    required bool forceRefresh,
  }) async {
    if (_gradesReadGuard() case final error?) throw error;
    final cache = _gradesCache();
    final options = await _loadAcademicTerms(forceRefresh: forceRefresh);
    if (!_gradesCurrent(cache)) throw _academicTermsConflict().error!;
    if (options.error case final error?) throw error;
    final selected = options.details.where((detail) {
      final term = detail.presentation;
      return term is TermPresentation &&
          term.selected &&
          term.code.trim().isNotEmpty;
    }).toList();
    if (selected.length != 1) return null;
    final detail = selected.single;
    final code = (detail.presentation! as TermPresentation).code;
    final result = await _readGradeTerm(
      cache,
      code,
      forceRefresh: forceRefresh,
    );
    if (!_gradesCurrent(cache)) throw _academicTermsConflict().error!;
    return GradeTermRead(code: code, name: detail.title, result: result);
  }

  void _rememberGradeResult(
    FeatureResult result,
    FeatureQuery? query, {
    bool fresh = true,
  }) {
    final cache = _gradesReadCache;
    if (cache == null || !_gradesCurrent(cache)) return;
    if (result.error case final error?) {
      if (error.kind == UbaaErrorKind.authentication) {
        cache.authenticationError = error;
        cache.entries.clear();
      } else {
        // 新读取失败后不再让随后换视图复活旧成功集合。
        final term = query?.term;
        if (term != null)
          cache.entries.remove(term);
        else
          cache.entries.clear();
      }
      return;
    }
    final overview = result.overview;
    if (overview is! GradesTermOverview ||
        overview.requestTerm != overview.termCode ||
        overview.requestTerm.trim().isEmpty)
      return;
    final term = overview.requestTerm;
    final entry = _GradeReadEntry()
      ..pending = false
      ..freshForAggregate = fresh;
    final stable = projectGrades(
      GradesTermOverview(
        requestTerm: term,
        termCode: term,
        grades: List.unmodifiable(overview.grades),
      ),
      FeatureQueryView.summary,
      result.resolvedRoute,
    );
    entry.result = stable;
    entry.completer.complete(stable);
    cache.entries[term] = entry;
  }

  FeatureResult? _cachedGradeQuery(FeatureQuery query) {
    if (!{
      FeatureQueryView.summary,
      FeatureQueryView.gradesScored,
      FeatureQueryView.gradesMissing,
    }.contains(query.view))
      return null;
    final cache = _gradesReadCache;
    if (cache == null ||
        !_gradesCurrent(cache) ||
        cache.authenticationError != null)
      return null;
    var term = query.term;
    if (term == null &&
        _academicTermsEpoch == _readCacheEpoch &&
        _academicTermsLifecycle == _lifecycleEpoch &&
        identical(_academicTermsBackend, _backend)) {
      final selected = _academicTermsResult?.details
          .map((d) => d.presentation)
          .whereType<TermPresentation>()
          .where((t) => t.selected)
          .toList();
      if (selected?.length == 1) term = selected!.single.code;
    }
    final entry = cache.entries[term];
    final result = entry?.result;
    final overview = result?.overview;
    if (entry?.pending != false ||
        result?.error != null ||
        overview is! GradesTermOverview ||
        overview.requestTerm != term ||
        overview.termCode != term)
      return null;
    return projectGrades(overview, query.view, result!.resolvedRoute);
  }

  UiError? _gradesReadGuard() {
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

  _GradesReadCache _gradesCache() {
    final existing = _gradesReadCache;
    if (existing != null &&
        _gradesCurrent(existing) &&
        existing.authenticationError == null)
      return existing;
    return _gradesReadCache = _GradesReadCache(
      _backend,
      _lifecycleEpoch,
      _readCacheEpoch,
    );
  }

  bool _gradesCurrent(_GradesReadCache cache) =>
      _gradesReadGuard() == null &&
      identical(_backend, cache.backend) &&
      identical(_gradesReadCache, cache) &&
      cache.lifecycle == _lifecycleEpoch &&
      cache.epoch == _readCacheEpoch;

  Future<FeatureResult> _loadGradeTerm(
    String term, {
    required bool forceRefresh,
  }) {
    if (_gradesReadGuard() case final error?) {
      return Future.value(FeatureResult.failure(error));
    }
    if (term.trim().isEmpty) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput),
        ),
      );
    }
    return _readGradeTerm(_gradesCache(), term, forceRefresh: forceRefresh);
  }

  Future<FeatureResult> _readGradeTerm(
    _GradesReadCache cache,
    String term, {
    required bool forceRefresh,
  }) {
    if (!_gradesCurrent(cache)) return Future.value(_academicTermsConflict());
    if (cache.authenticationError case final error?) {
      return Future.value(FeatureResult.failure(error));
    }
    final previous = cache.entries[term];
    if (previous != null && (previous.pending || !forceRefresh)) {
      return previous.completer.future;
    }
    final entry = _GradeReadEntry();
    cache.entries[term] = entry;
    unawaited(_fetchGradeTerm(cache, entry, term, forceRefresh: forceRefresh));
    return entry.completer.future;
  }

  Future<void> _fetchGradeTerm(
    _GradesReadCache cache,
    _GradeReadEntry entry,
    String term, {
    required bool forceRefresh,
  }) async {
    FeatureResult result;
    try {
      // 只复用已完成的完整集合；stale/loading与错学期不能成为统计基线。
      final sources = [
        _snapshots[FeatureId.grades],
        _homeDefaults[FeatureId.grades],
      ];
      FeatureResult? reusable;
      if (!forceRefresh) {
        for (final snapshot in sources) {
          final overview = snapshot?.overview;
          if (snapshot != null &&
              snapshot.error == null &&
              {
                FeatureLoadStatus.success,
                FeatureLoadStatus.empty,
              }.contains(snapshot.status) &&
              overview is GradesTermOverview &&
              overview.requestTerm == term &&
              overview.termCode == term) {
            reusable = FeatureResult.success(
              overview: overview,
              details: snapshot.details,
              resolvedRoute: snapshot.resolvedRoute,
            );
            break;
          }
        }
      }
      result =
          reusable ??
          await (cache.backend as FeatureQueryBackend).loadFeatureQuery(
            FeatureId.grades,
            FeatureQuery(term: term),
          );
      if (result.error == null) {
        final overview = result.overview;
        if (overview is! GradesTermOverview ||
            overview.requestTerm != term ||
            overview.termCode != term) {
          result = FeatureResult.failure(
            UbaaErrorMapper.fromCode(UbaaErrorCode.parseError),
          );
        } else {
          final stable = GradesTermOverview(
            requestTerm: term,
            termCode: term,
            grades: List.unmodifiable(overview.grades),
          );
          result = result.isEmpty
              ? FeatureResult.empty(
                  overview: stable,
                  resolvedRoute: result.resolvedRoute,
                )
              : FeatureResult.success(
                  overview: stable,
                  summary: result.summary,
                  details: List.unmodifiable(result.details),
                  resolvedRoute: result.resolvedRoute,
                );
        }
      }
    } on Object catch (error, stackTrace) {
      result = FeatureResult.failure(
        _recordFailure(
          error,
          DiagnosticOperation.read,
          feature: FeatureId.grades,
          stackTrace: stackTrace,
        ),
      );
    }
    if (!_gradesCurrent(cache)) {
      result = _academicTermsConflict();
    } else if (!identical(cache.entries[term], entry) &&
        cache.authenticationError == null) {
      // 当前领域更晚接受的完整集合优先，在途统计不得回填覆盖它。
      result = cache.entries[term]?.result ?? _academicTermsConflict();
    } else if (cache.authenticationError case final error?) {
      result = FeatureResult.failure(error);
    } else if (result.error case final error?) {
      result = FeatureResult.failure(
        _recordFailure(
          error,
          DiagnosticOperation.read,
          feature: FeatureId.grades,
        ),
      );
      if (error.kind == UbaaErrorKind.authentication) {
        cache.authenticationError = result.error;
        cache.entries.clear();
      }
    }
    if (result.error != null && identical(cache.entries[term], entry)) {
      cache.entries.remove(term);
    }
    entry.pending = false;
    entry.result = result;
    entry.completer.complete(result);
  }

  Future<GradesAggregate> _loadAllGrades({required bool forceRefresh}) {
    if (_gradesReadGuard() case final error?) {
      return Future.value(GradesAggregate(error: error));
    }
    final cache = _gradesCache();
    if (cache.aggregatePending case final pending?) return pending;
    final completer = Completer<GradesAggregate>();
    cache.aggregatePending = completer.future;
    unawaited(() async {
      try {
        completer.complete(
          await _fetchAllGrades(cache, forceRefresh: forceRefresh),
        );
      } on Object catch (error, stackTrace) {
        completer.complete(
          GradesAggregate(
            error: _recordFailure(
              error,
              DiagnosticOperation.read,
              feature: FeatureId.grades,
              stackTrace: stackTrace,
            ),
          ),
        );
      } finally {
        cache.aggregatePending = null;
      }
    }());
    return completer.future;
  }

  Future<GradesAggregate> _fetchAllGrades(
    _GradesReadCache cache, {
    required bool forceRefresh,
  }) async {
    final options = await _loadAcademicTerms(forceRefresh: forceRefresh);
    if (!_gradesCurrent(cache))
      return GradesAggregate(error: _academicTermsConflict().error);
    if (options.error != null) return GradesAggregate(error: options.error);
    final terms = <String, String>{};
    for (final detail in options.details) {
      final value = detail.presentation;
      if (value is TermPresentation && value.code.trim().isNotEmpty) {
        terms.putIfAbsent(value.code, () => detail.title);
      }
    }
    final reads = await Future.wait(
      terms.entries.map((term) async {
        final entry = cache.entries[term.key];
        final force = forceRefresh && !(entry?.freshForAggregate ?? false);
        if (entry != null) entry.freshForAggregate = false;
        return GradeTermRead(
          code: term.key,
          name: term.value,
          result: await _readGradeTerm(cache, term.key, forceRefresh: force),
        );
      }),
    );
    if (!_gradesCurrent(cache))
      return GradesAggregate(error: _academicTermsConflict().error);
    if (cache.authenticationError case final error?)
      return GradesAggregate(error: error);
    return GradesAggregate(terms: List.unmodifiable(reads));
  }
}
