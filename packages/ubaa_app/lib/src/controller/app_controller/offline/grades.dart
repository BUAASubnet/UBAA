part of '../../app_controller.dart';

extension _AppControllerOfflineGrades on AppController {
  Future<GradesAggregate> _loadGradesWithCache({
    required bool forceRefresh,
    void Function(GradesAggregate)? onProgress,
  }) async {
    final backend = _backend, account = _localAccount;
    final lifecycle = _lifecycleEpoch, epoch = _readCacheEpoch;
    final policy = _loginForm.routePolicy;
    bool current() =>
        !_disposed &&
        !_isSigningOut &&
        !_clearingBusinessCache &&
        _phase == AppPhase.home &&
        identical(backend, _backend) &&
        _localAccount?.id == account?.id &&
        lifecycle == _lifecycleEpoch &&
        epoch == _readCacheEpoch &&
        policy == _loginForm.routePolicy;
    final online = _loadAllGrades(forceRefresh: forceRefresh);
    if (account == null || backend is! OfflineQueryBackend) return online;
    var onlineFinished = false;
    final local = _readLocalGrades(
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
      return GradesAggregate(error: _academicTermsConflict().error);
    if (result.isComplete) return result;
    final saved = await local;
    if (!current())
      return GradesAggregate(error: _academicTermsConflict().error);
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

  Future<GradesAggregate?> _readLocalGrades(
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
          _localCacheError = _recordFailure(
            error,
            DiagnosticOperation.read,
            feature: feature,
            stackTrace: stackTrace,
          );
        return null;
      }
      if (!current()) return null;
      if (read.error != null)
        _localCacheError = _recordFailure(
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
      await _offlineOpenFuture;
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
        _localCacheError = _recordFailure(
          error,
          DiagnosticOperation.read,
          feature: FeatureId.grades,
          stackTrace: stackTrace,
        );
      return null;
    }
  }
}
