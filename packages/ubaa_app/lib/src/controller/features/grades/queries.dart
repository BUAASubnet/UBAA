import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/presentation/grades.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../../state/models.dart' show GradeReadEntry, GradesReadCache;
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase;

mixin ControllerGrades on ControllerState {
  @internal
  Future<FeatureResult>? internalReadSharedGradeQuery(FeatureQuery query) {
    if (query.term == null ||
        !{
          FeatureQueryView.summary,
          FeatureQueryView.gradesScored,
          FeatureQueryView.gradesMissing,
        }.contains(query.view))
      return null;
    // 主动查询绕过已完成缓存，但与同学期在途读取共用一次完整观察。
    return internalLoadGradeTerm(query.term!, forceRefresh: true).then((
      result,
    ) {
      final overview = result.overview;
      if (result.error != null || overview is! GradesTermOverview)
        return result;
      return projectGrades(
        overview,
        query.view,
        result.resolvedRoute,
        evidence: result.evidence,
      );
    });
  }

  @internal
  Future<GradeTermRead?> internalLoadCurrentGrades({
    required bool forceRefresh,
    required ReadPriority priority,
  }) async {
    if (internalGradesReadGuard() case final error?) throw error;
    final cache = internalGradesCache();
    final options = await internalLoadAcademicTerms(
      forceRefresh: forceRefresh,
      priority: priority,
    );
    if (!internalGradesCurrent(cache))
      throw internalAcademicTermsConflict().error!;
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
    final result = await internalReadGradeTerm(
      cache,
      code,
      forceRefresh: forceRefresh,
      priority: priority,
    );
    if (!internalGradesCurrent(cache))
      throw internalAcademicTermsConflict().error!;
    return GradeTermRead(code: code, name: detail.title, result: result);
  }

  @internal
  void internalRememberGradeResult(
    FeatureResult result,
    FeatureQuery? query, {
    bool fresh = true,
  }) {
    final cache = internalGradesReadCache;
    if (cache == null || !internalGradesCurrent(cache)) return;
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
    final entry = GradeReadEntry()
      ..pending = false
      ..freshForAggregate =
          fresh && result.evidence?.origin != DataOrigin.persisted;
    final stable = projectGrades(
      GradesTermOverview(
        requestTerm: term,
        termCode: term,
        grades: List.unmodifiable(overview.grades),
      ),
      FeatureQueryView.summary,
      result.resolvedRoute,
      evidence: result.evidence,
    );
    entry.result = stable;
    entry.completer.complete(stable);
    cache.entries[term] = entry;
  }

  @internal
  FeatureResult? internalCachedGradeQuery(FeatureQuery query) {
    if (!{
      FeatureQueryView.summary,
      FeatureQueryView.gradesScored,
      FeatureQueryView.gradesMissing,
    }.contains(query.view))
      return null;
    final cache = internalGradesReadCache;
    if (cache == null ||
        !internalGradesCurrent(cache) ||
        cache.authenticationError != null)
      return null;
    var term = query.term;
    if (term == null &&
        internalAcademicTermsEpoch == internalReadCacheEpoch &&
        internalAcademicTermsLifecycle == internalLifecycleEpoch &&
        identical(internalAcademicTermsBackend, internalBackend)) {
      final selected = internalAcademicTermsResult?.details
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
    return projectGrades(
      overview,
      query.view,
      result!.resolvedRoute,
      evidence: result.evidence,
    );
  }

  @internal
  UiError? internalGradesReadGuard() {
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
  GradesReadCache internalGradesCache() {
    final existing = internalGradesReadCache;
    if (existing != null &&
        internalGradesCurrent(existing) &&
        existing.authenticationError == null)
      return existing;
    return internalGradesReadCache = GradesReadCache(
      internalBackend,
      internalLifecycleEpoch,
      internalReadCacheEpoch,
    );
  }

  @internal
  bool internalGradesCurrent(GradesReadCache cache) =>
      internalGradesReadGuard() == null &&
      identical(internalBackend, cache.backend) &&
      identical(internalGradesReadCache, cache) &&
      cache.lifecycle == internalLifecycleEpoch &&
      cache.epoch == internalReadCacheEpoch;

  @internal
  Future<FeatureResult> internalLoadGradeTerm(
    String term, {
    required bool forceRefresh,
  }) {
    if (internalGradesReadGuard() case final error?) {
      return Future.value(FeatureResult.failure(error));
    }
    if (term.trim().isEmpty) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput),
        ),
      );
    }
    return internalReadGradeTerm(
      internalGradesCache(),
      term,
      forceRefresh: forceRefresh,
    );
  }

  @internal
  Future<FeatureResult> internalReadGradeTerm(
    GradesReadCache cache,
    String term, {
    required bool forceRefresh,
    ReadPriority priority = ReadPriority.interactive,
  }) {
    if (!internalGradesCurrent(cache))
      return Future.value(internalAcademicTermsConflict());
    if (cache.authenticationError case final error?) {
      return Future.value(FeatureResult.failure(error));
    }
    final previous = cache.entries[term];
    if (previous != null && (previous.pending || !forceRefresh)) {
      if (previous.pending && previous.demand.promote(priority)) {
        internalReadScheduler.pump();
      }
      return previous.completer.future;
    }
    final entry = GradeReadEntry(priority);
    cache.entries[term] = entry;
    unawaited(
      internalFetchGradeTerm(cache, entry, term, forceRefresh: forceRefresh),
    );
    return entry.completer.future;
  }

  @internal
  Future<void> internalFetchGradeTerm(
    GradesReadCache cache,
    GradeReadEntry entry,
    String term, {
    required bool forceRefresh,
  }) async {
    FeatureResult result;
    try {
      // 只复用已完成的完整集合；stale/loading与错学期不能成为统计基线。
      final sources = [
        internalSnapshots[FeatureId.grades],
        internalHomeDefaults[FeatureId.grades],
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
              evidence: snapshot.evidence,
              resolvedRoute: snapshot.resolvedRoute,
            );
            break;
          }
        }
      }
      result =
          reusable ??
          await internalScheduleAuxiliaryRead(
            cache.backend,
            FeatureId.grades,
            ReadPriority.interactive,
            () => internalGradesCurrent(cache),
            () => (cache.backend as FeatureQueryBackend).loadFeatureQuery(
              FeatureId.grades,
              FeatureQuery(term: term),
            ),
            demand: entry.demand,
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
                  evidence: result.evidence,
                  resolvedRoute: result.resolvedRoute,
                )
              : FeatureResult.success(
                  overview: stable,
                  evidence: result.evidence,
                  summary: result.summary,
                  details: List.unmodifiable(result.details),
                  resolvedRoute: result.resolvedRoute,
                );
        }
      }
    } on Object catch (error, stackTrace) {
      result = FeatureResult.failure(
        internalRecordFailure(
          error,
          DiagnosticOperation.read,
          feature: FeatureId.grades,
          stackTrace: stackTrace,
        ),
      );
    }
    if (!internalGradesCurrent(cache)) {
      result = internalAcademicTermsConflict();
    } else if (!identical(cache.entries[term], entry) &&
        cache.authenticationError == null) {
      // 当前领域更晚接受的完整集合优先，在途统计不得回填覆盖它。
      result = cache.entries[term]?.result ?? internalAcademicTermsConflict();
    } else if (cache.authenticationError case final error?) {
      result = FeatureResult.failure(error);
    } else if (result.error case final error?) {
      result = FeatureResult.failure(
        internalRecordFailure(
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

  @internal
  Future<GradesAggregate> internalLoadAllGrades({required bool forceRefresh}) {
    if (internalGradesReadGuard() case final error?) {
      return Future.value(GradesAggregate(error: error));
    }
    final cache = internalGradesCache();
    if (cache.aggregatePending case final pending?) return pending;
    final completer = Completer<GradesAggregate>();
    cache.aggregatePending = completer.future;
    unawaited(() async {
      try {
        completer.complete(
          await internalFetchAllGrades(cache, forceRefresh: forceRefresh),
        );
      } on Object catch (error, stackTrace) {
        completer.complete(
          GradesAggregate(
            error: internalRecordFailure(
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

  @internal
  Future<GradesAggregate> internalFetchAllGrades(
    GradesReadCache cache, {
    required bool forceRefresh,
  }) async {
    final options = await internalLoadAcademicTerms(forceRefresh: forceRefresh);
    if (!internalGradesCurrent(cache))
      return GradesAggregate(error: internalAcademicTermsConflict().error);
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
          result: await internalReadGradeTerm(
            cache,
            term.key,
            forceRefresh: force,
          ),
        );
      }),
    );
    if (!internalGradesCurrent(cache))
      return GradesAggregate(error: internalAcademicTermsConflict().error);
    if (cache.authenticationError case final error?)
      return GradesAggregate(error: error);
    return GradesAggregate(
      terms: List.unmodifiable(reads),
      termsEvidence: options.evidence,
    );
  }
}
