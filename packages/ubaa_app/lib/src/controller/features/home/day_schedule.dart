part of 'sources.dart';

Future<FeatureResult> _loadHomeDay(
  ControllerState owner,
  String date,
  bool force,
) {
  if (owner.internalDisposed ||
      owner.internalReadTransitionBlocked ||
      owner.internalLegacyReadSessionBlocked) {
    return Future.value(owner.internalAcademicTermsConflict());
  }
  if (owner.internalPhase != AppPhase.home) {
    return Future.value(
      FeatureResult.failure(
        UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired),
      ),
    );
  }
  final day = homeParseDate(date), backend = owner.internalBackend;
  if (day == null ||
      homeDateKey(day) != date ||
      backend is! FeatureQueryBackend) {
    return Future.value(
      FeatureResult.failure(
        UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput),
      ),
    );
  }
  var cache = owner.internalReadCaches.home;
  if (cache == null ||
      !identical(cache.backend, backend) ||
      cache.lifecycle != owner.internalLifecycleEpoch ||
      cache.epoch != owner.internalReadCacheEpoch) {
    cache = HomeSupplementCache(
      backend,
      owner.internalLifecycleEpoch,
      owner.internalReadCacheEpoch,
    );
    owner.internalReadCaches.home = cache;
  }
  final previous = cache.days[date];
  if (previous != null && (previous.pending || !force))
    return previous.completer.future;
  final entry = HomeSupplementEntry();
  cache.days[date] = entry;
  final activeCache = cache;
  final scope = owner.internalCaptureReadScope();
  bool current() =>
      scope.isCurrent &&
      owner.internalPhase == AppPhase.home &&
      identical(owner.internalReadCaches.home, activeCache) &&
      identical(activeCache.days[date], entry);
  unawaited(() async {
    try {
      var result = await _fetchHomeDay(owner, day, force, current);
      if (current() && result.error != null) {
        result = FeatureResult.failure(
          owner.internalRecordFailure(
            result.error!,
            DiagnosticOperation.read,
            feature: FeatureId.schedule,
          ),
        );
      }
      entry.completer.complete(
        current() ? result : owner.internalAcademicTermsConflict(),
      );
    } on Object catch (error, stack) {
      entry.completer.complete(
        current()
            ? FeatureResult.failure(
                owner.internalRecordFailure(
                  error,
                  DiagnosticOperation.read,
                  feature: FeatureId.schedule,
                  stackTrace: stack,
                ),
              )
            : owner.internalAcademicTermsConflict(),
      );
    } finally {
      entry.pending = false;
    }
  }());
  return entry.completer.future;
}

Future<FeatureResult> _fetchHomeDay(
  ControllerState owner,
  DateTime day,
  bool force,
  bool Function() current,
) async {
  final terms = await _homeCalendarRead(
    owner,
    const FeatureQuery(view: FeatureQueryView.scheduleTerms),
    force,
    current,
  );
  if (!current()) return owner.internalAcademicTermsConflict();
  if (terms.error != null) return terms;
  if (terms.evidence?.complete == false)
    return _homeCalendarUnknown('学期索引暂未加载完整');
  final selected = terms.details
      .map((d) => d.presentation)
      .whereType<TermPresentation>()
      .where((t) => t.selected && t.code.trim().isNotEmpty)
      .toList();
  if (selected.length != 1) return _homeCalendarUnknown('当前学期未确定');
  final term = selected.single.code;
  final weeks = await _homeCalendarRead(
    owner,
    FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
    force,
    current,
  );
  if (!current()) return owner.internalAcademicTermsConflict();
  if (weeks.error != null) return weeks;
  if (weeks.evidence?.complete == false)
    return _homeCalendarUnknown('教学周索引暂未加载完整');
  final week = homeWeekOn(
    weeks.details.map((d) => d.presentation).whereType<WeekPresentation>(),
    day,
    term: term,
  );
  if (week == null) return _homeCalendarUnknown('该日期的教学周未确定');
  final weekly = await _homeCalendarRead(
    owner,
    FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: term,
      week: week.number,
    ),
    force,
    current,
  );
  if (!current()) return owner.internalAcademicTermsConflict();
  if (weekly.error != null) return weekly;
  if (weekly.evidence?.complete == false)
    return _homeCalendarUnknown('课表暂未加载完整');
  return homeProjectScheduleDay(weekly, week, day);
}

FeatureResult _homeCalendarUnknown(String message) => FeatureResult.failure(
  UiError(
    code: UbaaErrorCode.invalidInput,
    title: '课表暂不可用',
    message: message,
    retryable: true,
  ),
);

Future<FeatureResult> _homeCalendarRead(
  ControllerState owner,
  FeatureQuery query,
  bool force,
  bool Function() current,
) async {
  final backend = owner.internalBackend;
  final account = owner.internalLocalAccount;
  final policy = owner.internalLoginForm.routePolicy;
  Future<FeatureResult?> saved() async {
    if (backend is! OfflineQueryBackend || account == null) return null;
    try {
      await owner.internalOfflineOpenFuture;
      if (!current()) return null;
      final read = await (backend as OfflineQueryBackend).readCachedQuery(
        FeatureId.schedule,
        query,
        policy,
      );
      if (!current()) return null;
      if (read.error != null)
        owner.internalRecordFailure(
          read.error!,
          DiagnosticOperation.read,
          feature: FeatureId.schedule,
        );
      final p = read.projection;
      if (p == null ||
          !p.complete ||
          p.accountId != account.id ||
          p.feature != FeatureId.schedule ||
          !p.readContext.hasSameQuery(query) ||
          (policy == RoutePolicy.direct && p.route != ConnectionMode.direct) ||
          (policy == RoutePolicy.webvpn && p.route != ConnectionMode.webvpn))
        return null;
      final evidence = p.toSnapshot().evidence;
      return p.details.isEmpty
          ? FeatureResult.empty(
              overview: p.overview,
              evidence: evidence,
              resolvedRoute: p.route,
            )
          : FeatureResult.success(
              details: p.details,
              overview: p.overview,
              evidence: evidence,
              resolvedRoute: p.route,
            );
    } on Object catch (error, stack) {
      if (current())
        owner.internalRecordFailure(
          error,
          DiagnosticOperation.read,
          feature: FeatureId.schedule,
          stackTrace: stack,
        );
      return null;
    }
  }

  if (!force) {
    final local = await saved();
    if (local != null) return local;
  }
  if (!current()) return owner.internalAcademicTermsConflict();
  final result = switch (query.view) {
    FeatureQueryView.scheduleTerms => await owner.internalLoadAcademicTerms(
      forceRefresh: force,
      priority: ReadPriority.home,
    ),
    FeatureQueryView.scheduleWeeks => await owner.internalLoadAcademicWeeks(
      query.term!,
      forceRefresh: force,
    ),
    _ => await owner.internalScheduleAuxiliaryRead(
      backend,
      FeatureId.schedule,
      ReadPriority.home,
      current,
      () => (backend as FeatureQueryBackend).loadFeatureQuery(
        FeatureId.schedule,
        query,
      ),
    ),
  };
  if (!current()) return owner.internalAcademicTermsConflict();
  // 强制刷新失败保持失败语义，用户可以重试；正常打开可使用完整本地课表。
  return result;
}
