part of '../bridge_backend.dart';

Future<FeatureResult> _loadYgdkOverviewOnRoute(
  BridgeBackend backend, {
  required ConnectionMode route,
}) async {
  try {
    final result = await backend.client.ygdkOverviewOnRoute(
      route: _toBridgeConnectionMode(route),
    );
    return _mapYgdkOverviewResult(
      result.data,
      _toConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<FeatureResult> _loadYgdkRecordsOnRoute(
  BridgeBackend backend, {
  required ConnectionMode route,
  required int page,
  required int size,
}) async {
  if (page <= 0 || size <= 0) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  try {
    final result = await backend.client.ygdkRecordsOnRoute(
      route: _toBridgeConnectionMode(route),
      page: page,
      size: size,
    );
    return _mapYgdkRecordsResult(
      result.data,
      _toConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<FeatureResult> _loadYgdkFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query, {
  bool includeRecords = false,
}) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.ygdk:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.ygdkOverview();
          YgdkHomeRecords? records;
          if (includeRecords) {
            final page = query.page <= 0 ? 1 : query.page;
            final size = query.size.clamp(1, 100);
            try {
              final response = await client.ygdkRecordsOnRoute(
                route: result.route.resolvedRoute,
                page: page,
                size: size,
              );
              if (response.pinnedRoute != result.route.resolvedRoute) {
                throw const BackendException(UbaaErrorCode.internalError);
              }
              records = YgdkHomeRecords(
                page: response.data.page,
                size: response.data.size,
                total: response.data.total,
                hasMore: response.data.hasMore,
                content: List.unmodifiable(
                  response.data.content.map(_ygdkRecordPresentation),
                ),
              );
            } on BridgeError catch (error) {
              // 认证失效交给原控制器；其他局部失败保留概要，不伪造空记录。
              if (error.kind == BridgeErrorKind.authentication) rethrow;
              records = YgdkHomeRecords(
                page: page,
                size: size,
                errorCode: _typedErrorCode(error.code),
              );
            }
          }
          return _mapYgdkOverviewResult(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
            records: records,
          );
        case FeatureQueryView.ygdkRecords:
          final page = query.page <= 0 ? 1 : query.page;
          final size = query.size.clamp(1, 100);
          final result = await client.ygdkRecords(page: page, size: size);
          return _mapYgdkRecordsResult(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.libbookAreas:
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
        case FeatureQueryView.libbookAreaDetail:
        case FeatureQueryView.libbookSeats:
        case FeatureQueryView.libbookBookings:
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

FeatureResult _mapYgdkOverviewResult(
  BridgeYgdkOverview data,
  ConnectionMode resolvedRoute, {
  YgdkHomeRecords? records,
}) {
  final itemIdCounts = <int, int>{};
  for (final item in data.items) {
    itemIdCounts.update(item.itemId, (count) => count + 1, ifAbsent: () => 1);
  }
  final details = data.items
      .map(
        (item) => FeatureDetail(
          title: item.name,
          presentation: YgdkItemPresentation(
            itemId: item.itemId,
            name: item.name,
            kind: item.kind,
            sort: item.sort,
          ),
          fields: _compactFields(<FeatureField?>[
            _field('项目编号', '${item.itemId}'),
            item.kind == null ? null : _field('类型', '${item.kind}'),
          ]),
          actions: _ygdkSubmitActions(data, item, itemIdCounts),
        ),
      )
      .toList(growable: false);
  final summary = data.summary.termTarget == null
      ? '已打卡 ${data.summary.termCount} 次'
      : '学期进度 ${data.summary.termCount}/${data.summary.termTarget}';
  return FeatureResult.success(
    summary: summary,
    overview: YgdkOverview(
      termId: data.summary.termId,
      termName: data.summary.termName,
      termCount: data.summary.termCount,
      termTarget: data.summary.termTarget,
      weekCount: data.summary.weekCount,
      weekTarget: data.summary.weekTarget,
      monthCount: data.summary.monthCount,
      monthTarget: data.summary.monthTarget,
      dayCount: data.summary.dayCount,
      goodCount: data.summary.goodCount,
      classifyId: data.classifyId,
      classifyName: data.classifyName,
      defaultItemId: data.defaultItemId,
      defaultItemName: data.defaultItemName,
      records: records,
    ),
    details: details,
    resolvedRoute: resolvedRoute,
  );
}

FeatureResult _mapYgdkRecordsResult(
  BridgeYgdkRecordsPage data,
  ConnectionMode resolvedRoute,
) {
  final details = data.content
      .map(
        (item) => FeatureDetail(
          title: item.itemName ?? '打卡记录 ${item.recordId}',
          subtitle: item.createdAtLabel ?? item.createdAt,
          presentation: _ygdkRecordPresentation(item),
          fields: _compactFields(<FeatureField?>[
            _field('记录编号', '${item.recordId}'),
            _field('开始时间', item.startTime),
            _field('结束时间', item.endTime),
            _field('地点', item.place),
            _field('公开状态', item.isOpen ? '公开' : '不公开'),
            _field('图片数量', '${item.imageCount}'),
          ]),
        ),
      )
      .toList(growable: false);
  return _countResult(
    data.content.length,
    '条打卡记录',
    details: details,
    pagination: _pagination(
      page: data.page,
      size: data.size,
      total: data.total,
      hasMore: data.hasMore,
    ),
    resolvedRoute: resolvedRoute,
  );
}

List<FeatureAction> _ygdkSubmitActions(
  BridgeYgdkOverview overview,
  BridgeYgdkItem item,
  Map<int, int> itemIdCounts,
) {
  if (overview.classifyId <= 0 ||
      overview.classifyName.trim().isEmpty ||
      item.itemId <= 0 ||
      item.name.trim().isEmpty ||
      itemIdCounts[item.itemId] != 1) {
    return const <FeatureAction>[];
  }
  final target = item.submitTarget;
  if (item.submitEligibility != BridgeActionEligibility.allowed ||
      target == null ||
      target.classifyId != overview.classifyId ||
      target.itemId != item.itemId ||
      target.classifyId <= 0 ||
      target.itemId <= 0) {
    return const <FeatureAction>[];
  }
  return <FeatureAction>[
    YgdkSubmitAction(
      classifyId: target.classifyId,
      itemId: target.itemId,
      eligibility: _toYgdkActionEligibility(item.submitEligibility),
    ),
  ];
}

ActionEligibility _toYgdkActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

YgdkRecordPresentation _ygdkRecordPresentation(BridgeYgdkRecord item) =>
    YgdkRecordPresentation(
      recordId: item.recordId,
      itemId: item.itemId,
      itemName: item.itemName,
      startTime: item.startTime,
      endTime: item.endTime,
      place: item.place,
      imageCount: item.imageCount,
      isOpen: item.isOpen,
      state: item.state,
      createdAt: item.createdAt,
      createdAtLabel: item.createdAtLabel,
    );
