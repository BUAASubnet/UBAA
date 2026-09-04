part of '../bridge_backend.dart';

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
            '个可预约场馆',
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
          final details = <FeatureDetail>[];
          for (final space in result.data.spaces) {
            for (final slot in space.slots) {
              final eligibility = _toCgyyActionEligibility(
                slot.reservationEligibility,
              );
              final target = slot.reservationTarget;
              if (eligibility != ActionEligibility.allowed ||
                  target == null ||
                  target.venueSiteId <= 0 ||
                  target.reservationDate.trim().isEmpty ||
                  target.spaceId <= 0 ||
                  target.timeId <= 0 ||
                  target.timeOrdinal < 0 ||
                  (target.venueSpaceGroupId != null &&
                      target.venueSpaceGroupId! <= 0)) {
                continue;
              }
              final matchingSlots = result.data.timeSlots
                  .where((item) => item.id == slot.timeId)
                  .toList(growable: false);
              final timeSlot = matchingSlots.isEmpty
                  ? null
                  : matchingSlots.first;
              details.add(
                FeatureDetail(
                  title:
                      '${space.spaceName} ${timeSlot?.label ?? '时段 ${slot.timeId}'}',
                  fields: _compactFields(<FeatureField?>[
                    _field('站点 ID', '${result.data.venueSiteId}'),
                    _field('日期', result.data.reservationDate),
                    _field('空间 ID', '${space.spaceId}'),
                    _field('空间组 ID', space.venueSpaceGroupId?.toString()),
                    _field('时段 ID', '${slot.timeId}'),
                    _field('开始时间', timeSlot?.beginTime),
                    _field('结束时间', timeSlot?.endTime),
                    _field('可预约', '是'),
                  ]),
                  actions: <FeatureAction>[
                    CgyyReserveAction(
                      venueSiteId: target.venueSiteId,
                      reservationDate: target.reservationDate.trim(),
                      spaceId: target.spaceId,
                      timeId: target.timeId,
                      venueSpaceGroupId: target.venueSpaceGroupId,
                      timeOrdinal: target.timeOrdinal,
                      eligibility: eligibility,
                    ),
                  ],
                ),
              );
            }
          }
          return _countResult(
            details.length,
            '个可预约时段',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyOrders:
          final page = query.page <= 0 ? 1 : query.page;
          final size = query.size.clamp(1, 100);
          final result = await client.cgyyOrders(page: page, size: size);
          final details = result.data.content
              .map(
                (item) => FeatureDetail(
                  title: item.theme ?? item.siteName ?? '场馆订单 ${item.id}',
                  subtitle: item.venueSpaceName ?? item.venueName,
                  fields: _compactFields(<FeatureField?>[
                    _field('订单编号', '${item.id}'),
                    _field(
                      '日期',
                      item.reservationDateDetail ?? item.reservationDate,
                    ),
                    _field('开始', item.reservationStartDate),
                    _field('结束', item.reservationEndDate),
                    _field('用途', item.purposeTypeName),
                    item.joinerNum == null
                        ? null
                        : _field('参与人数', '${item.joinerNum}'),
                    _field('订单状态', item.orderStatus?.toString()),
                    _field('审核状态', item.checkStatus?.toString()),
                    _field(
                      '订单状态说明',
                      _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
                    ),
                    _field('审核状态说明', _cgyyCheckStatusText(item.checkStatus)),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.content.length,
            '条场馆订单',
            details: details,
            pagination: _pagination(
              page: result.data.number,
              size: result.data.size,
              total: result.data.totalElements,
              totalPages: result.data.totalPages,
            ),
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyOrderDetail:
          final orderId = _requiredPositiveInt(query.orderId, '订单 ID');
          final result = await client.cgyyOrderDetail(id: orderId);
          final item = result.data;
          return FeatureResult.success(
            summary: '订单详情',
            details: <FeatureDetail>[
              FeatureDetail(
                title: item.theme ?? item.siteName ?? '场馆订单 ${item.id}',
                subtitle: item.venueSpaceName ?? item.venueName,
                fields: _compactFields(<FeatureField?>[
                  _field('订单编号', '${item.id}'),
                  _field('校区', item.campusName),
                  _field(
                    '日期',
                    item.reservationDateDetail ?? item.reservationDate,
                  ),
                  _field('开始', item.reservationStartDate),
                  _field('结束', item.reservationEndDate),
                  _field('用途', item.purposeTypeName),
                  item.joinerNum == null
                      ? null
                      : _field('参与人数', '${item.joinerNum}'),
                  _field('订单状态', item.orderStatus?.toString()),
                  _field('审核状态', item.checkStatus?.toString()),
                  _field(
                    '订单状态说明',
                    _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
                  ),
                  _field('审核状态说明', _cgyyCheckStatusText(item.checkStatus)),
                ]),
              ),
            ],
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.cgyyLockCode:
          final result = await client.cgyyLockCode();
          return FeatureResult.success(
            summary: result.data.available ? '门锁可用' : '门锁不可用',
            details: <FeatureDetail>[
              FeatureDetail(
                title: '门锁状态',
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
