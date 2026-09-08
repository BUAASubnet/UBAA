part of '../bridge_backend.dart';

Future<FeatureResult> _loadCgyyOrdersOnRoute(
  BridgeBackend backend, {
  required ConnectionMode route,
  required int page,
  required int size,
}) async {
  if (page < 0 || size <= 0) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  try {
    final result = await backend.client.cgyyOrdersOnRoute(
      route: _toBridgeConnectionMode(route),
      page: page,
      size: size,
    );
    return _mapCgyyOrdersResult(
      result.data,
      _toConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<FeatureResult> _loadCgyyOrderDetailOnRoute(
  BridgeBackend backend, {
  required ConnectionMode route,
  required int orderId,
}) async {
  if (orderId <= 0) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  try {
    final result = await backend.client.cgyyOrderDetailOnRoute(
      route: _toBridgeConnectionMode(route),
      id: orderId,
    );
    return _mapCgyyOrderDetailResult(
      result.data,
      _toConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<FeatureResult> _loadCgyyFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
  String today,
) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.cgyy:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.cgyySites();
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.siteName,
                  subtitle: item.venueName,
                  presentation: CgyySitePresentation(
                    id: item.id,
                    siteName: item.siteName,
                    venueName: item.venueName,
                    campusName: item.campusName,
                    seatCount: item.seatCount,
                    reservationSpaceCount: item.reservationSpaceCount,
                    openStartDate: item.openStartDate,
                    openEndDate: item.openEndDate,
                    queryDate: today,
                  ),
                  readNavigation: item.id <= 0
                      ? null
                      : FeatureReadNavigation(
                          feature: FeatureId.cgyy,
                          query: FeatureQuery(
                            view: FeatureQueryView.cgyyDayInfo,
                            siteId: item.id,
                            date: DateTime.parse(today),
                          ),
                        ),
                  fields: _compactFields(<FeatureField?>[
                    _field('站点 ID', '${item.id}'),
                    _field('校区', item.campusName),
                    item.seatCount == null
                        ? null
                        : _field('座位数', '${item.seatCount}'),
                    item.reservationSpaceCount == null
                        ? null
                        : _field('空间数', '${item.reservationSpaceCount}'),
                    _field('开放开始', item.openStartDate),
                    _field('开放结束', item.openEndDate),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.length,
            '个研讨室预约站点',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyPurposeTypes:
          final result = await client.cgyyPurposeTypes();
          final source = result.data.source == BridgeCgyyPurposeSource.upstream
              ? '上游'
              : '本地冻结回退';
          final details = result.data.items
              .map(
                (item) => FeatureDetail(
                  title: item.name,
                  presentation: CgyyPurposePresentation(
                    key: item.key,
                    name: item.name,
                    isStaticFallback:
                        result.data.source ==
                        BridgeCgyyPurposeSource.staticFallback,
                  ),
                  fields: <FeatureField>[
                    FeatureField(label: '用途编号', value: '${item.key}'),
                    FeatureField(label: '来源', value: source),
                  ],
                ),
              )
              .toList(growable: false);
          return FeatureResult.success(
            summary: '用途类型（来源：$source）',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyDayInfo:
          final siteId = _requiredPositiveInt(query.siteId, '站点 ID');
          final result = await client.cgyyDayInfo(siteId: siteId, date: today);
          return _mapCgyyDayInfo(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyOrders:
          final page = query.page <= 0 ? 1 : query.page;
          final size = query.size.clamp(1, 100);
          final result = await client.cgyyOrders(page: page, size: size);
          return _mapCgyyOrdersResult(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyOrderDetail:
          final orderId = _requiredPositiveInt(query.orderId, '订单 ID');
          final result = await client.cgyyOrderDetail(id: orderId);
          return _mapCgyyOrderDetailResult(
            result.data,
            _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyLockCode:
          final result = await client.cgyyLockCode();
          return FeatureResult.success(
            summary: result.data.available ? '门锁可用' : '门锁不可用',
            details: <FeatureDetail>[
              FeatureDetail(
                title: '门锁状态',
                presentation: CgyyLockPresentation(
                  available: result.data.available,
                ),
                fields: <FeatureField>[
                  FeatureField(
                    label: '可用',
                    value: result.data.available ? '是' : '否',
                  ),
                ],
              ),
            ],
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
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
        case FeatureQueryView.ygdkRecords:
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

FeatureResult _mapCgyyOrdersResult(
  BridgeCgyyOrdersPage data,
  ConnectionMode resolvedRoute,
) {
  final details = data.content
      .map(
        (item) => FeatureDetail(
          title: item.theme ?? item.siteName ?? '研讨室订单 ${item.id}',
          subtitle: item.venueSpaceName ?? item.venueName,
          presentation: _cgyyOrderPresentation(item),
          readNavigation: item.id <= 0
              ? null
              : FeatureReadNavigation(
                  feature: FeatureId.cgyy,
                  query: FeatureQuery(
                    view: FeatureQueryView.cgyyOrderDetail,
                    orderId: item.id,
                  ),
                ),
          fields: _compactFields(<FeatureField?>[
            _field('订单编号', '${item.id}'),
            _field('日期', item.reservationDateDetail ?? item.reservationDate),
            _field('开始', item.reservationStartDate),
            _field('结束', item.reservationEndDate),
            _field('用途', item.purposeTypeName),
            item.joinerNum == null ? null : _field('参与人数', '${item.joinerNum}'),
            _field('订单状态', item.orderStatus?.toString()),
            _field('审核状态', item.checkStatus?.toString()),
            _field(
              '订单状态说明',
              _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
            ),
            _field('审核状态说明', _cgyyCheckStatusText(item.checkStatus)),
          ]),
          actions: _cgyyCancelActions(item),
        ),
      )
      .toList(growable: false);
  return _countResult(
    data.content.length,
    '条研讨室订单',
    details: details,
    pagination: _pagination(
      page: data.number,
      size: data.size,
      total: data.totalElements,
      totalPages: data.totalPages,
    ),
    resolvedRoute: resolvedRoute,
  );
}

FeatureResult _mapCgyyOrderDetailResult(
  BridgeCgyyOrder item,
  ConnectionMode resolvedRoute,
) => FeatureResult.success(
  summary: '订单详情',
  details: <FeatureDetail>[
    FeatureDetail(
      title: item.theme ?? item.siteName ?? '研讨室订单 ${item.id}',
      subtitle: item.venueSpaceName ?? item.venueName,
      presentation: _cgyyOrderPresentation(item),
      fields: _compactFields(<FeatureField?>[
        _field('订单编号', '${item.id}'),
        _field('校区', item.campusName),
        _field('日期', item.reservationDateDetail ?? item.reservationDate),
        _field('开始', item.reservationStartDate),
        _field('结束', item.reservationEndDate),
        _field('用途', item.purposeTypeName),
        item.joinerNum == null ? null : _field('参与人数', '${item.joinerNum}'),
        _field('订单状态', item.orderStatus?.toString()),
        _field('审核状态', item.checkStatus?.toString()),
        _field(
          '订单状态说明',
          _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
        ),
        _field('审核状态说明', _cgyyCheckStatusText(item.checkStatus)),
      ]),
      actions: _cgyyCancelActions(item),
    ),
  ],
  resolvedRoute: resolvedRoute,
);

List<FeatureAction> _cgyyCancelActions(BridgeCgyyOrder item) {
  if (item.id <= 0) return const <FeatureAction>[];
  return <FeatureAction>[
    CgyyCancelAction(
      orderId: item.id,
      orderStatus: item.orderStatus,
      checkStatus: item.checkStatus,
      targetOrderId: item.cancelTarget?.orderId,
      cancelledTargetOrderId: item.cancelledTarget?.orderId,
      eligibility: _toCgyyActionEligibility(item.cancelEligibility),
    ),
  ];
}

ActionEligibility _toCgyyActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

String? _cgyyCheckStatusText(int? status) => switch (status) {
  1 => '审批通过',
  2 => '待辅导员审批',
  -2 => '辅导员审批驳回',
  3 => '待副书记/副处长审批',
  -3 => '副书记/副处长审批驳回',
  4 => '待宣传部审批',
  -4 => '宣传部审批驳回',
  5 => '待国交处备案',
  -5 => '国交处备案驳回',
  6 => '待教务处审批',
  -6 => '教务处驳回',
  _ => null,
};

String _cgyyOrderStatusText(int? orderStatus, int? checkStatus) {
  if ((checkStatus ?? 0) < 0) {
    return _cgyyCheckStatusText(checkStatus) ?? '审批驳回';
  }
  return switch (orderStatus) {
    2 => '已取消',
    1 when checkStatus == 1 => '审批通过',
    1 when (checkStatus ?? 0) > 0 => '待审批',
    3 => '占用',
    1 => '正常',
    final value => value == null ? '未知' : '未知($value)',
  };
}

CgyyOrderPresentation _cgyyOrderPresentation(BridgeCgyyOrder item) =>
    CgyyOrderPresentation(
      id: item.id,
      venueSiteId: item.venueSiteId,
      reservationDate: item.reservationDate,
      reservationDateDetail: item.reservationDateDetail,
      venueSpaceName: item.venueSpaceName,
      campusName: item.campusName,
      venueName: item.venueName,
      siteName: item.siteName,
      reservationStartDate: item.reservationStartDate,
      reservationEndDate: item.reservationEndDate,
      orderStatus: item.orderStatus,
      checkStatus: item.checkStatus,
      theme: item.theme,
      purposeTypeName: item.purposeTypeName,
      joinerNum: item.joinerNum,
      statusText: _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
      checkStatusText: _cgyyCheckStatusText(item.checkStatus),
    );
