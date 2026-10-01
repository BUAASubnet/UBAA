part of '../bridge_backend.dart';

bool _isBykcCacheQuery(FeatureId feature, FeatureQuery query) =>
    feature == FeatureId.bykc &&
    {
      FeatureQueryView.summary,
      FeatureQueryView.bykcDetail,
      FeatureQueryView.bykcProfile,
      FeatureQueryView.bykcChosenCourses,
      FeatureQueryView.bykcStatistics,
    }.contains(query.view);
Future<CachedFeatureProjection?> _cachedBykcProjection(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route,
) async {
  FeatureResult result;
  late int fetchedAt;
  late bool complete;
  late BridgeConnectionMode source;
  FeatureOverview? overview;
  switch (query.view) {
    case FeatureQueryView.summary:
      final value = await cache.readBykcCourses(
        route: route,
        page: query.page <= 0 ? 1 : query.page,
        size: query.size.clamp(1, 100),
        all: true,
      );
      if (value == null) return null;
      result = _projectBykcCourses(
        _cachedBykcPage(value.data),
        _toConnectionMode(value.sourceRoute),
        requestedPage: query.page <= 0 ? 1 : query.page,
        requestedSize: query.size.clamp(1, 100),
        catalog: {
          for (final item in value.data.content)
            item.id: _cachedBykcCatalog(item),
        },
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    case FeatureQueryView.bykcDetail:
      final value = await cache.readBykcDetail(
        route: route,
        courseId: _requiredPositiveQueryInt(query.courseId, '课程 ID'),
      );
      if (value == null) return null;
      if (value.data.id != _requiredPositiveQueryInt(query.courseId, '课程 ID'))
        throw const BackendException(UbaaErrorCode.internalError);
      result = _projectBykcDetail(
        _cachedBykcCourse(value.data),
        _toConnectionMode(value.sourceRoute),
        catalog: _cachedBykcCatalog(value.data),
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    case FeatureQueryView.bykcProfile:
      final value = await cache.readBykcProfile(route: route);
      if (value == null) return null;
      result = _projectBykcProfile(
        value.data,
        _toConnectionMode(value.sourceRoute),
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    case FeatureQueryView.bykcChosenCourses:
      final value = await cache.readBykcChosen(route: route);
      if (value == null) return null;
      result = _projectBykcChosen(
        value.data.courses.map(_cachedBykcChosen).toList(),
        _toConnectionMode(value.sourceRoute),
        persisted: true,
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
      overview = BykcChosenOverview(
        semesterStart: value.data.semesterStart,
        semesterEnd: value.data.semesterEnd,
      );
    case FeatureQueryView.bykcStatistics:
      final value = await cache.readBykcStatistics(route: route);
      if (value == null) return null;
      result = _projectBykcStatistics(
        value.data,
        _toConnectionMode(value.sourceRoute),
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    default:
      return null;
  }
  return CachedFeatureProjection(
    feature: FeatureId.bykc,
    query: query,
    accountId: account.id,
    route: _toConnectionMode(source),
    fetchedAt: _cacheTime(fetchedAt),
    complete: complete,
    details: result.details,
    overview: overview ?? result.overview,
    pagination: result.pagination,
  );
}

BridgeBykcCourse _cachedBykcCourse(BridgeCachedBykcCourse v) =>
    BridgeBykcCourse(
      id: v.id,
      courseName: v.courseName,
      coursePosition: v.coursePosition,
      courseTeacher: v.courseTeacher,
      courseStartDate: v.courseStartDate,
      courseEndDate: v.courseEndDate,
      courseSelectStartDate: v.courseSelectStartDate,
      courseSelectEndDate: v.courseSelectEndDate,
      courseCancelEndDate: v.courseCancelEndDate,
      courseMaxCount: v.courseMaxCount,
      courseCurrentCount: v.courseCurrentCount,
      status: v.status,
      selected: v.selected,
      selectEligibility: BridgeActionEligibility.unknown,
      deselectEligibility: BridgeActionEligibility.unknown,
    );
BridgeBykcChosenCourse _cachedBykcChosen(BridgeCachedBykcChosenCourse v) =>
    BridgeBykcChosenCourse(
      id: v.id,
      courseId: v.courseId,
      courseName: v.courseName,
      coursePosition: v.coursePosition,
      courseTeacher: v.courseTeacher,
      courseStartDate: v.courseStartDate,
      courseEndDate: v.courseEndDate,
      selectDate: v.selectDate,
      courseCancelEndDate: v.courseCancelEndDate,
      category: v.category,
      subCategory: v.subCategory,
      checkin: v.checkin,
      score: v.score,
      pass: v.pass,
      signEligibility: BridgeActionEligibility.unknown,
      signOutEligibility: BridgeActionEligibility.unknown,
      deselectEligibility: BridgeActionEligibility.unknown,
      signConfig: v.signWindow == null
          ? null
          : BridgeBykcSignConfig(
              signStartDate: v.signWindow!.signStartDate,
              signEndDate: v.signWindow!.signEndDate,
              signOutStartDate: v.signWindow!.signOutStartDate,
              signOutEndDate: v.signWindow!.signOutEndDate,
              signPoints: const [],
            ),
      courseSignType: v.courseSignType,
    );
BridgeBykcCoursePage _cachedBykcPage(BridgeCachedBykcCoursePage v) =>
    BridgeBykcCoursePage(
      content: v.content.map(_cachedBykcCourse).toList(),
      number: v.number,
      size: v.size,
      totalElements: v.totalElements,
      totalPages: v.totalPages,
    );

/// 错详情不得生成动作；只能继续显示同账号、路线和查询的旧只读内容。
Future<FeatureResult> _preserveBykcDetail(
  BridgeBackend backend,
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  ConnectionMode route,
) async {
  final old = await _cachedBykcProjection(
    cache,
    account,
    query,
    _toBridgeConnectionMode(route),
  );
  if (backend._offlineAccount?.id != account.id)
    throw const BackendException(UbaaErrorCode.operationConflict);
  if (old == null)
    throw BackendException(
      UbaaErrorCode.upstreamChanged,
      kind: UbaaErrorKind.upstream,
      retryable: false,
      resolvedRoute: route,
    );
  return FeatureResult.success(
    summary: '课程详情尚未核对完整',
    details: old.details,
    resolvedRoute: old.route,
    evidence: DataEvidence(
      accountId: account.id,
      origin: DataOrigin.persisted,
      fetchedAt: old.fetchedAt,
      complete: false,
      savedForOffline: false,
    ),
  );
}

BridgeBykcCourseCatalogItem _cachedBykcCatalog(BridgeCachedBykcCourse value) =>
    BridgeBykcCourseCatalogItem(
      course: _cachedBykcCourse(value),
      category: value.category,
      subCategory: value.subCategory,
      audienceCampuses: value.audienceCampuses ?? const [],
      hasSignPoints: value.hasSignPoints ?? false,
    );
