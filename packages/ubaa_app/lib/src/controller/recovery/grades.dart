import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/offline.dart';
import 'package:ubaa_app/src/presentation/grades.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase;

mixin ControllerOfflineGrades on ControllerState {
  @internal
  Future<GradesAggregate> internalLoadGradesWithCache({
    required bool forceRefresh,
    void Function(GradesAggregate)? onProgress,
  }) async {
    final backend = internalBackend, account = internalLocalAccount;
    final lifecycle = internalLifecycleEpoch, epoch = internalReadCacheEpoch;
    final policy = internalLoginForm.routePolicy;
    bool current() =>
        !internalDisposed &&
        !internalIsSigningOut &&
        !internalClearingBusinessCache &&
        internalPhase == AppPhase.home &&
        identical(backend, internalBackend) &&
        internalLocalAccount?.id == account?.id &&
        lifecycle == internalLifecycleEpoch &&
        epoch == internalReadCacheEpoch &&
        policy == internalLoginForm.routePolicy;
    final online = internalLoadAllGrades(forceRefresh: forceRefresh);
    if (account == null || backend is! OfflineQueryBackend) return online;
    var onlineFinished = false;
    final local = internalReadLocalGrades(
      backend as OfflineQueryBackend,
      account,
      policy,
      current,
    );
    unawaited(
      local.then((value) {
        if (!onlineFinished && current() && value != null)
          onProgress?.call(value);
      }),
    );
    final result = await online;
    onlineFinished = true;
    if (!current())
      return GradesAggregate(error: internalAcademicTermsConflict().error);
    if (result.isComplete) return result;
    final saved = await local;
    if (!current())
      return GradesAggregate(error: internalAcademicTermsConflict().error);
    if (saved == null) return result;
    if (result.terms.isEmpty)
      return GradesAggregate(
        terms: saved.terms,
        termsEvidence: saved.termsEvidence,
        error: result.error,
      );
    final old = {for (final term in saved.terms) term.code: term};
    return GradesAggregate(
      termsEvidence: result.termsEvidence,
      error:
          result.error ??
          result.terms
              .map((term) => term.result.error)
              .whereType<UiError>()
              .firstOrNull,
      terms: List.unmodifiable(
        result.terms.map((term) {
          final previous = old[term.code];
          return term.overview == null &&
                  previous?.overview != null &&
                  (term.resolvedRoute == null ||
                      term.resolvedRoute == previous!.resolvedRoute)
              ? previous!
              : term;
        }),
      ),
    );
  }

  @internal
  Future<GradesAggregate?> internalReadLocalGrades(
    OfflineQueryBackend backend,
    LocalAccount account,
    RoutePolicy policy,
    bool Function() current,
  ) async {
    Future<FeatureResult?> read(FeatureId feature, FeatureQuery query) async {
      if (!current()) return null;
      OfflineQueryRead read;
      try {
        read = await backend.readCachedQuery(feature, query, policy);
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
      return FeatureResult.success(
        details: snapshot.details,
        overview: snapshot.overview,
        evidence: snapshot.evidence,
        resolvedRoute: snapshot.resolvedRoute,
      );
    }

    try {
      await internalOfflineOpenFuture;
      final options = await read(
        FeatureId.schedule,
        const FeatureQuery(view: FeatureQueryView.scheduleTerms),
      );
      if (options == null || !current()) return null;
      final terms = <String, String>{};
      for (final detail in options.details) {
        final term = detail.presentation;
        if (term is TermPresentation && term.code.trim().isNotEmpty)
          terms.putIfAbsent(term.code, () => detail.title);
      }
      final values = <GradeTermRead>[];
      for (final term in terms.entries) {
        var result = await read(FeatureId.grades, FeatureQuery(term: term.key));
        final overview = result?.overview;
        if (overview is! GradesTermOverview ||
            overview.requestTerm != term.key ||
            overview.termCode != term.key)
          result = null;
        values.add(
          GradeTermRead(
            code: term.key,
            name: term.value,
            result: result == null
                ? FeatureResult.failure(
                    const UiError(
                      code: UbaaErrorCode.unsupported,
                      title: '学期尚未保存',
                      message: '连接后可读取此学期成绩。',
                    ),
                  )
                : projectGrades(
                    result.overview! as GradesTermOverview,
                    FeatureQueryView.summary,
                    result.resolvedRoute,
                    evidence: result.evidence,
                  ),
          ),
        );
      }
      if (!current()) return null;
      return GradesAggregate(
        terms: List.unmodifiable(values),
        termsEvidence: options.evidence,
      );
    } on Object catch (error, stackTrace) {
      if (current())
        internalLocalCacheError = internalRecordFailure(
          error,
          DiagnosticOperation.read,
          feature: FeatureId.grades,
          stackTrace: stackTrace,
        );
      return null;
    }
  }
}
