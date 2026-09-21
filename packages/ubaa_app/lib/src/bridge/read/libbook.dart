part of '../bridge_backend.dart';

Future<FeatureResult> _loadLibbookFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
  String today, {
  bool useCache = true,
}) async {
  if (useCache && _isLibbookCacheQuery(feature, query)) {
    final cached = await _loadCachedLibbookFeature(backend, query, today);
    if (cached != null) return cached;
  }
  final client = backend.client;
  switch (feature) {
    case FeatureId.libbook:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.libbookLibraries(day: today);
          return _projectLibbookLibraries(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.libbookAreas:
          final premisesId = _requiredQueryValue(query.premisesId, '馆区 ID');
          final result = await client.libbookAreas(
            premisesId: premisesId,
            storeyId: query.storeyId,
            day: today,
          );
          return _projectLibbookAreas(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.libbookAreaDetail:
          final areaId = _requiredQueryValue(query.areaId, '分区 ID');
          final result = await client.libbookAreaDetail(areaId: areaId);
          return _projectLibbookAreaDetail(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.libbookSeats:
          final areaId = _requiredQueryValue(query.areaId, '分区 ID');
          _requiredQueryValue(query.segment, '时段');
          final startTime = _requiredQueryValue(query.startTime, '开始时间');
          final endTime = _requiredQueryValue(query.endTime, '结束时间');
          final result = await client.libbookSeats(
            areaId: areaId,
            day: today,
            startTime: startTime,
            endTime: endTime,
          );
          return _projectLibbookSeats(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.libbookBookings:
          final page = query.page <= 0 ? 1 : query.page;
          final limit = query.size.clamp(1, 100);
          final result = await client.libbookBookings(page: page, limit: limit);
          return _projectLibbookBookings(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
            today,
            query,
          );
        case FeatureQueryView.ygdkRecords:
        case FeatureQueryView.bykcDetail:
        case FeatureQueryView.bykcProfile:
        case FeatureQueryView.bykcChosenCourses:
        case FeatureQueryView.bykcStatistics:
        case FeatureQueryView.scheduleToday:
        case FeatureQueryView.scheduleTerms:
        case FeatureQueryView.scheduleWeeks:
        case FeatureQueryView.scheduleWeek:
        case FeatureQueryView.examArranged:
        case FeatureQueryView.examNotArranged:
        case FeatureQueryView.gradesScored:
        case FeatureQueryView.gradesMissing:
        case FeatureQueryView.evaluationPending:
        case FeatureQueryView.cgyyPurposeTypes:
        case FeatureQueryView.cgyyDayInfo:
        case FeatureQueryView.cgyyOrders:
        case FeatureQueryView.cgyyOrderDetail:
        case FeatureQueryView.cgyyLockCode:
        case FeatureQueryView.spocDetail:
        case FeatureQueryView.judgeDetail:
        case FeatureQueryView.judgeBatchDetails:
        case FeatureQueryView.signinPending:
        case FeatureQueryView.signinCompleted:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    default:
      throw StateError('unexpected feature: $feature');
  }
}

ActionEligibility _toLibbookActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

String _libbookEligibilityLabel(ActionEligibility eligibility) =>
    switch (eligibility) {
      ActionEligibility.allowed => '是',
      ActionEligibility.denied => '否',
      ActionEligibility.unknown => '未知',
    };
