part of '../bridge_backend.dart';

final class _AcademicCacheMiss implements Exception {
  const _AcademicCacheMiss();
}

final class _AcademicValue<T> {
  const _AcademicValue(this.data, this.route);
  final T data;
  final ConnectionMode route;
}

/// 在线和磁盘只改变数据来源，共用同一 typed 展示映射。
final class _AcademicReader {
  _AcademicReader(this.backend, {this.localRoute});
  final BridgeBackend backend;
  final BridgeConnectionMode? localRoute;
  DataEvidence? evidence;
  void record(
    LocalAccount account,
    int fetchedAt,
    bool complete,
    bool saved, {
    String? date,
  }) {
    evidence = DataEvidence(
      accountId: account.id,
      origin: localRoute == null ? DataOrigin.online : DataOrigin.persisted,
      fetchedAt: _cacheTime(fetchedAt),
      complete: complete,
      savedForOffline: saved,
      scopeDate: date,
    );
  }

  Future<_AcademicValue<List<BridgeTerm>>> scheduleTerms() async {
    await _awaitOfflineScope(backend);
    final cache = backend._offlineCache;
    final account = backend._offlineAccount;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const _AcademicCacheMiss();
      final value = await cache.readAcademicTerms(route: route);
      if (value == null) throw const _AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return _AcademicValue(value.data, _toConnectionMode(value.sourceRoute));
    }
    if (cache != null && account != null) {
      final value = await backend.client.academicTermsCached(cache: cache);
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        value.saveError == null,
        date: null,
      );
      return _AcademicValue(
        value.result.data,
        _toConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.scheduleTerms();
    evidence = null;
    return _AcademicValue(
      value.data,
      _toConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<_AcademicValue<List<BridgeWeek>>> scheduleWeeks({
    required String term,
  }) async {
    await _awaitOfflineScope(backend);
    final cache = backend._offlineCache;
    final account = backend._offlineAccount;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const _AcademicCacheMiss();
      final value = await cache.readAcademicWeeks(route: route, term: term);
      if (value == null) throw const _AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return _AcademicValue(value.data, _toConnectionMode(value.sourceRoute));
    }
    if (cache != null && account != null) {
      final value = await backend.client.academicWeeksCached(
        cache: cache,
        term: term,
      );
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        value.saveError == null,
        date: null,
      );
      return _AcademicValue(
        value.result.data,
        _toConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.scheduleWeeks(term: term);
    evidence = null;
    return _AcademicValue(
      value.data,
      _toConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<_AcademicValue<BridgeWeeklySchedule>> scheduleWeek({
    required String term,
    required int week,
  }) async {
    await _awaitOfflineScope(backend);
    final cache = backend._offlineCache;
    final account = backend._offlineAccount;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const _AcademicCacheMiss();
      final value = await cache.readAcademicWeek(
        route: route,
        term: term,
        week: week,
      );
      if (value == null) throw const _AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return _AcademicValue(value.data, _toConnectionMode(value.sourceRoute));
    }
    if (cache != null && account != null) {
      final value = await backend.client.academicWeekCached(
        cache: cache,
        term: term,
        week: week,
      );
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        value.saveError == null,
        date: null,
      );
      return _AcademicValue(
        value.result.data,
        _toConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.scheduleWeek(term: term, week: week);
    evidence = null;
    return _AcademicValue(
      value.data,
      _toConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<_AcademicValue<BridgeExamArrangement>> examArrangement({
    required String term,
  }) async {
    await _awaitOfflineScope(backend);
    final cache = backend._offlineCache;
    final account = backend._offlineAccount;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const _AcademicCacheMiss();
      final value = await cache.readAcademicExams(route: route, term: term);
      if (value == null) throw const _AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return _AcademicValue(value.data, _toConnectionMode(value.sourceRoute));
    }
    if (cache != null && account != null) {
      final value = await backend.client.academicExamsCached(
        cache: cache,
        term: term,
      );
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        value.saveError == null,
        date: null,
      );
      return _AcademicValue(
        value.result.data,
        _toConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.examArrangement(term: term);
    evidence = null;
    return _AcademicValue(
      value.data,
      _toConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<_AcademicValue<BridgeGradeData>> grades({required String term}) async {
    await _awaitOfflineScope(backend);
    final cache = backend._offlineCache;
    final account = backend._offlineAccount;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const _AcademicCacheMiss();
      final value = await cache.readAcademicGrades(route: route, term: term);
      if (value == null) throw const _AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return _AcademicValue(value.data, _toConnectionMode(value.sourceRoute));
    }
    if (cache != null && account != null) {
      final value = await backend.client.academicGradesCached(
        cache: cache,
        term: term,
      );
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        value.saveError == null,
        date: null,
      );
      return _AcademicValue(
        value.result.data,
        _toConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.grades(term: term);
    evidence = null;
    return _AcademicValue(
      value.data,
      _toConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<_AcademicValue<BridgeClassroomQuery>> classroomSearch({
    required int campus,
    required String date,
  }) async {
    await _awaitOfflineScope(backend);
    final cache = backend._offlineCache;
    final account = backend._offlineAccount;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const _AcademicCacheMiss();
      final value = await cache.readAcademicClassrooms(
        route: route,
        campus: campus,
        date: date,
      );
      if (value == null) throw const _AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: date,
      );
      return _AcademicValue(value.data, _toConnectionMode(value.sourceRoute));
    }
    if (cache != null && account != null) {
      final value = await backend.client.academicClassroomsCached(
        cache: cache,
        campus: campus,
        date: date,
      );
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        value.saveError == null,
        date: date,
      );
      return _AcademicValue(
        value.result.data,
        _toConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.classroomSearch(
      campus: campus,
      date: date,
    );
    evidence = null;
    return _AcademicValue(
      value.data,
      _toConnectionMode(value.route.resolvedRoute),
    );
  }
}

FeatureResult _academicEvidence(FeatureResult result, DataEvidence? evidence) {
  if (evidence == null) return result;
  if (!evidence.complete)
    return FeatureResult.success(
      summary: '本次响应的完整性尚未确认',
      details: result.details,
      overview: result.overview,
      resolvedRoute: result.resolvedRoute,
      evidence: evidence,
    );
  return result.isEmpty
      ? FeatureResult.empty(
          overview: result.overview,
          resolvedRoute: result.resolvedRoute,
          evidence: evidence,
        )
      : FeatureResult.success(
          summary: result.summary,
          details: result.details,
          overview: result.overview,
          resolvedRoute: result.resolvedRoute,
          evidence: evidence,
        );
}

bool _isAcademicCacheQuery(FeatureId feature, FeatureQuery query) =>
    switch (feature) {
      FeatureId.schedule =>
        query.view == FeatureQueryView.scheduleTerms ||
            query.view == FeatureQueryView.scheduleWeeks ||
            query.view == FeatureQueryView.scheduleWeek ||
            (query.view == FeatureQueryView.summary &&
                query.term != null &&
                query.week != null),
      FeatureId.exam => {
        FeatureQueryView.summary,
        FeatureQueryView.examArranged,
        FeatureQueryView.examNotArranged,
      }.contains(query.view),
      FeatureId.grades => {
        FeatureQueryView.summary,
        FeatureQueryView.gradesScored,
        FeatureQueryView.gradesMissing,
      }.contains(query.view),
      FeatureId.classroom => true,
      _ => false,
    };

Future<CachedFeatureProjection?> _cachedAcademicProjection(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
  BridgeConnectionMode route,
  LocalAccount account,
  String queryDate,
) async {
  final reader = _AcademicReader(backend, localRoute: route);
  try {
    final result = await _projectAcademicFeature(
      backend,
      reader,
      feature,
      query,
      queryDate,
    );
    final evidence = reader.evidence;
    if (evidence == null || result.resolvedRoute == null) return null;
    return CachedFeatureProjection(
      feature: feature,
      query: query,
      accountId: account.id,
      route: result.resolvedRoute!,
      fetchedAt: evidence.fetchedAt,
      complete: evidence.complete,
      scopeDate: evidence.scopeDate,
      details: result.details,
      overview: result.overview is GradesTermOverview
          ? result.overview as GradesTermOverview
          : null,
    );
  } on _AcademicCacheMiss {
    return null;
  }
}
