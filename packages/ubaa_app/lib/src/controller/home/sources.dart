part of 'coordinator.dart';

extension _HomeSources on HomeCoordinator {
  Future<void> _restoreVisibleDay() async {
    final read = readCachedDay;
    if (read == null || !_active || !_readDays || _blocked) return;
    final schedule = _scheduleState();
    if (!schedule.remote) return;
    final date = schedule.date;
    await _cachedDayTasks.putIfAbsent(date, () async {
      final generation = _generation;
      final result = await read(date);
      if (_disposed ||
          generation != _generation ||
          result == null ||
          result.overview is! HomeScheduleOverview ||
          (result.overview! as HomeScheduleOverview).date != date)
        return;
      final previous = _days[date];
      if (previous?.updatedAt != null || previous?.evidence != null) return;
      _days[date] = _snapshot(FeatureId.schedule, result, previous);
      _schedule();
    });
    // 午夜后先补今日，今日已结束时继续补实际展示的明日。
    if (!_disposed && _scheduleState().date != date) await _restoreVisibleDay();
  }

  Map<FeatureId, FeatureSnapshot> _sources() {
    final sources = <FeatureId, FeatureSnapshot>{
      for (final f in [
        FeatureId.schedule,
        FeatureId.signin,
        FeatureId.spoc,
        FeatureId.judge,
        FeatureId.ygdk,
        FeatureId.exam,
        FeatureId.bykc,
        FeatureId.cgyy,
      ])
        f: _snapshots[f] ?? FeatureSnapshot(feature: f),
    };
    for (final (source, feature) in [
      (HomeSupplement.bykcChosen, FeatureId.bykc),
      (HomeSupplement.cgyyOrders, FeatureId.cgyy),
    ]) {
      final result = _supplements[source];
      if (result != null)
        sources[feature] = _snapshot(
          feature,
          result,
          sources[feature],
          at: _supplementTimes[source],
        );
      if (_supplementTasks.containsKey(source)) {
        sources[feature] = sources[feature]!.copyWith(
          status: FeatureLoadStatus.loading,
        );
      }
    }
    return sources;
  }

  Future<void> _load(HomeSupplement source, {bool force = false}) {
    if (_supplementTasks[source] case final pending?) return pending;
    final generation = _generation, epoch = _epoch;
    final done = Completer<void>();
    _supplementTasks[source] = done.future;
    _supplementAttempts.add(source);
    _publish();
    unawaited(() async {
      try {
        final result = await loadSupplement(source, force);
        if (_disposed || generation != _generation) return;
        if (result.error != null && epoch != _epoch) {
          _supplementAttempts.remove(source);
          if (_active && !_blocked && (_online || _refresh != null)) {
            _supplementTasks.remove(source);
            await _load(source, force: force || _refresh != null);
          }
          return;
        }
        final old = _supplements[source];
        _supplements[source] = _retain(result, old);
        if (result.error == null) _supplementTimes[source] = clock();
        _dirtyProjection = true;
      } on Object catch (error) {
        if (!_disposed && generation == _generation) {
          _supplements[source] = _retain(_failure(error), _supplements[source]);
        }
      } finally {
        if (identical(_supplementTasks[source], done.future))
          _supplementTasks.remove(source);
        done.complete();
        _schedule();
      }
    }());
    return done.future;
  }

  void _restoreWeek() {
    final read = readCachedWeek;
    if (read == null || !_active) return;
    final generation = _generation;
    _cachedWeekTask = () async {
      try {
        final result = await read(_now);
        if (_disposed || generation != _generation || result == null) return;
        final previous = _supplements[HomeSupplement.currentWeek];
        if (previous != null &&
            previous.evidence?.origin != DataOrigin.persisted)
          return;
        _supplements[HomeSupplement.currentWeek] = result;
        _dirtyProjection = true;
        _schedule();
      } on Object {
        // 本机读取错误由 Controller 记录，缺失缓存不阻塞在线来源。
      }
    }();
  }

  HomeScheduleState _scheduleState() {
    final now = homeCampusTime(_now), date = homeDateKey(now);
    final today =
        _snapshots[FeatureId.schedule] ??
        const FeatureSnapshot(feature: FeatureId.schedule);
    final matches = (today.evidence?.scopeDate ?? _observedToday) == date;
    final current = matches ? today : _days[date];
    final courses =
        current?.details
            .where((d) => d.presentation is TodayCoursePresentation)
            .toList() ??
        const <FeatureDetail>[];
    final complete =
        current != null &&
        current.evidence?.complete != false &&
        (current.status == FeatureLoadStatus.success ||
            current.status == FeatureLoadStatus.empty ||
            current.updatedAt != null);
    final tomorrow =
        _readDays &&
        complete &&
        (courses.isEmpty || homeCoursesFinished(courses, now, now));
    final target = tomorrow ? DateTime(now.year, now.month, now.day + 1) : now;
    final key = homeDateKey(target), remote = tomorrow || !matches;
    final snapshot = remote
        ? _days[key] ?? const FeatureSnapshot(feature: FeatureId.schedule)
        : today;
    return HomeScheduleState(
      date: key,
      tomorrow: tomorrow,
      remote: remote,
      snapshot: _dayTasks.containsKey(key)
          ? snapshot.copyWith(status: FeatureLoadStatus.loading)
          : snapshot,
    );
  }

  Future<void> _loadDay(String date, {bool force = false}) {
    if (_dayTasks[date] case final pending?) return pending;
    final generation = _generation, epoch = _epoch;
    final done = Completer<void>();
    _dayTasks[date] = done.future;
    _dayAttempts.add(date);
    _publish();
    unawaited(() async {
      try {
        var result = await loadDay(date, force);
        if (_disposed || generation != _generation) return;
        if (epoch != _epoch) {
          _dayAttempts.remove(date);
          return;
        }
        if (result.error == null &&
            (result.overview is! HomeScheduleOverview ||
                (result.overview! as HomeScheduleOverview).date != date)) {
          result = const FeatureResult.failure(
            UiError(
              code: UbaaErrorCode.invalidInput,
              title: '课表暂不可用',
              message: '课表日期未确认',
              retryable: true,
            ),
          );
        }
        _days[date] = _snapshot(FeatureId.schedule, result, _days[date]);
      } on Object catch (error) {
        if (!_disposed && generation == _generation) {
          _days[date] = _snapshot(
            FeatureId.schedule,
            _failure(error),
            _days[date],
          );
        }
      } finally {
        if (identical(_dayTasks[date], done.future)) _dayTasks.remove(date);
        done.complete();
        _schedule();
      }
    }());
    return done.future;
  }
}

FeatureResult _failure(Object error) => FeatureResult.failure(
  error is UiError
      ? error
      : const UiError(
          code: UbaaErrorCode.internalError,
          title: '读取失败',
          message: '来源暂时无法更新',
          retryable: true,
        ),
);

FeatureResult _retain(FeatureResult result, FeatureResult? previous) =>
    result.error != null &&
        result.details.isEmpty &&
        result.overview == null &&
        previous != null &&
        (previous.details.isNotEmpty ||
            previous.overview != null ||
            previous.evidence != null)
    ? FeatureResult.partial(
        error: result.error!,
        details: previous.details,
        overview: previous.overview,
        evidence: previous.evidence,
        resolvedRoute: previous.resolvedRoute,
        pagination: previous.pagination,
      )
    : result;

FeatureSnapshot _snapshot(
  FeatureId feature,
  FeatureResult result,
  FeatureSnapshot? previous, {
  DateTime? at,
}) {
  if (result.error != null &&
      result.evidence == null &&
      result.details.isEmpty &&
      result.overview == null &&
      previous != null &&
      (previous.updatedAt != null || previous.evidence != null)) {
    return previous.copyWith(
      status: FeatureLoadStatus.stale,
      error: result.error,
    );
  }
  return FeatureSnapshot(
    feature: feature,
    status: result.error != null
        ? (result.evidence != null ||
                  result.details.isNotEmpty ||
                  result.overview != null
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.failure)
        : result.evidence?.complete == false ||
              result.evidence?.origin == DataOrigin.persisted
        ? FeatureLoadStatus.stale
        : result.isEmpty
        ? FeatureLoadStatus.empty
        : FeatureLoadStatus.success,
    details: result.details,
    overview: result.overview,
    summary: result.summary,
    error: result.error,
    evidence: result.evidence,
    resolvedRoute: result.resolvedRoute,
    pagination: result.pagination,
    updatedAt:
        result.evidence?.fetchedAt ??
        (result.error == null ? at ?? DateTime.now() : previous?.updatedAt),
  );
}
