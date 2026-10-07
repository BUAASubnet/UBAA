part of 'reader.dart';

/// 在线和磁盘只改变数据来源，共用同一 typed 展示映射。
final class _AcademicReader {
  _AcademicReader(this.backend, {this.localRoute});
  final BridgeContext backend;
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
      fetchedAt: bridgeCacheTime(fetchedAt),
      complete: complete,
      savedForOffline: saved,
      scopeDate: date,
    );
  }

  Future<AcademicValue<List<BridgeTerm>>> scheduleTerms() async {
    await bridgeAwaitOfflineScope(backend);
    final cache = backend.cache.handle;
    final account = backend.cache.account;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const AcademicCacheMiss();
      final value = await cache.readAcademicTerms(route: route);
      if (value == null) throw const AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return AcademicValue(
        value.data,
        bridgeToConnectionMode(value.sourceRoute),
      );
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
      return AcademicValue(
        value.result.data,
        bridgeToConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.scheduleTerms();
    evidence = null;
    return AcademicValue(
      value.data,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<AcademicValue<List<BridgeWeek>>> scheduleWeeks({
    required String term,
  }) async {
    await bridgeAwaitOfflineScope(backend);
    final cache = backend.cache.handle;
    final account = backend.cache.account;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const AcademicCacheMiss();
      final value = await cache.readAcademicWeeks(route: route, term: term);
      if (value == null) throw const AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return AcademicValue(
        value.data,
        bridgeToConnectionMode(value.sourceRoute),
      );
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
      return AcademicValue(
        value.result.data,
        bridgeToConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.scheduleWeeks(term: term);
    evidence = null;
    return AcademicValue(
      value.data,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<AcademicValue<BridgeWeeklySchedule>> scheduleWeek({
    required String term,
    required int week,
  }) async {
    await bridgeAwaitOfflineScope(backend);
    final cache = backend.cache.handle;
    final account = backend.cache.account;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const AcademicCacheMiss();
      final value = await cache.readAcademicWeek(
        route: route,
        term: term,
        week: week,
      );
      if (value == null) throw const AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return AcademicValue(
        value.data,
        bridgeToConnectionMode(value.sourceRoute),
      );
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
      return AcademicValue(
        value.result.data,
        bridgeToConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.scheduleWeek(term: term, week: week);
    evidence = null;
    return AcademicValue(
      value.data,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<AcademicValue<BridgeExamArrangement>> examArrangement({
    required String term,
  }) async {
    await bridgeAwaitOfflineScope(backend);
    final cache = backend.cache.handle;
    final account = backend.cache.account;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const AcademicCacheMiss();
      final value = await cache.readAcademicExams(route: route, term: term);
      if (value == null) throw const AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return AcademicValue(
        value.data,
        bridgeToConnectionMode(value.sourceRoute),
      );
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
      return AcademicValue(
        value.result.data,
        bridgeToConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.examArrangement(term: term);
    evidence = null;
    return AcademicValue(
      value.data,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<AcademicValue<BridgeGradeData>> grades({required String term}) async {
    await bridgeAwaitOfflineScope(backend);
    final cache = backend.cache.handle;
    final account = backend.cache.account;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const AcademicCacheMiss();
      final value = await cache.readAcademicGrades(route: route, term: term);
      if (value == null) throw const AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: null,
      );
      return AcademicValue(
        value.data,
        bridgeToConnectionMode(value.sourceRoute),
      );
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
      return AcademicValue(
        value.result.data,
        bridgeToConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.grades(term: term);
    evidence = null;
    return AcademicValue(
      value.data,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  }

  Future<AcademicValue<BridgeClassroomQuery>> classroomSearch({
    required int campus,
    required String date,
  }) async {
    await bridgeAwaitOfflineScope(backend);
    final cache = backend.cache.handle;
    final account = backend.cache.account;
    final route = localRoute;
    if (route != null) {
      if (cache == null || account == null) throw const AcademicCacheMiss();
      final value = await cache.readAcademicClassrooms(
        route: route,
        campus: campus,
        date: date,
      );
      if (value == null) throw const AcademicCacheMiss();
      record(
        account,
        value.fetchedAt.toInt(),
        value.complete,
        true,
        date: date,
      );
      return AcademicValue(
        value.data,
        bridgeToConnectionMode(value.sourceRoute),
      );
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
      return AcademicValue(
        value.result.data,
        bridgeToConnectionMode(value.result.route.resolvedRoute),
      );
    }
    final value = await backend.client.classroomSearch(
      campus: campus,
      date: date,
    );
    evidence = null;
    return AcademicValue(
      value.data,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  }
}

Future<CachedFeatureProjection?> bridgeCachedAcademicProjection(
  BridgeContext backend,
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
      overview:
          result.overview is GradesTermOverview ||
              result.overview is ScheduleWeekOverview
          ? result.overview
          : null,
    );
  } on AcademicCacheMiss {
    return null;
  }
}
