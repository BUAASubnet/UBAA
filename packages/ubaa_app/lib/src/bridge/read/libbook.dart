part of '../bridge_backend.dart';

Future<FeatureResult> _loadLibbookFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
  String today,
) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.libbook:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.libbookLibraries(day: today);
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.name,
                  fields: _compactFields(<FeatureField?>[
                    _field('馆 ID', item.id),
                    _field('空闲座位', '${item.freeNum}'),
                    _field('总座位', '${item.totalNum}'),
                    _field('楼层数', '${item.storeys.length}'),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.length,
            '所图书馆',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.libbookAreas:
          final premisesId = _requiredQueryValue(query.premisesId, '馆区 ID');
          final result = await client.libbookAreas(
            premisesId: premisesId,
            storeyId: query.storeyId,
            day: today,
          );
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.name,
                  subtitle: item.areaName,
                  fields: _compactFields(<FeatureField?>[
                    _field('分区 ID', item.id),
                    _field('楼层 ID', item.storeyId),
                    _field('空闲座位', '${item.freeNum}'),
                    _field('总座位', '${item.totalNum}'),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.length,
            '个图书馆分区',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.libbookAreaDetail:
          final areaId = _requiredQueryValue(query.areaId, '分区 ID');
          final result = await client.libbookAreaDetail(areaId: areaId);
          final detail = result.data;
          return FeatureResult.success(
            summary: '可用日期 ${detail.availableDates.length} 天',
            details: <FeatureDetail>[
              FeatureDetail(
                title: detail.name,
                fields: _compactFields(<FeatureField?>[
                  _field('分区 ID', detail.id),
                  _field(
                    '可用日期',
                    detail.availableDates.isEmpty
                        ? null
                        : detail.availableDates.join('、'),
                  ),
                  _field(
                    '时段',
                    detail.timeSlots.isEmpty
                        ? null
                        : detail.timeSlots.map((slot) => slot.label).join('、'),
                  ),
                ]),
              ),
            ],
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.libbookSeats:
          final areaId = _requiredQueryValue(query.areaId, '分区 ID');
          final segment = _requiredQueryValue(query.segment, '时段');
          final startTime = _requiredQueryValue(query.startTime, '开始时间');
          final endTime = _requiredQueryValue(query.endTime, '结束时间');
          final result = await client.libbookSeats(
            areaId: areaId,
            day: today,
            startTime: startTime,
            endTime: endTime,
          );
          final details = result.data
              .map((item) {
                final target = item.reserveTarget?.trim();
                final eligibility = _toLibbookActionEligibility(
                  item.reserveEligibility,
                );
                return FeatureDetail(
                  title: item.name,
                  subtitle: item.no,
                  fields: _compactFields(<FeatureField?>[
                    _field('分区 ID', areaId),
                    _field('座位 ID', item.id),
                    _field('日期', today),
                    _field('时段', segment),
                    _field('开始时间', startTime),
                    _field('结束时间', endTime),
                    _field('状态码', item.status?.toString()),
                    _field('状态', item.statusName),
                    _field('可预约', _libbookEligibilityLabel(eligibility)),
                  ]),
                  actions: target == null || target.isEmpty
                      ? const <FeatureAction>[]
                      : <FeatureAction>[
                          LibbookReserveAction(
                            areaId: areaId,
                            seatId: target,
                            day: today,
                            segment: segment,
                            startTime: startTime,
                            endTime: endTime,
                            eligibility: eligibility,
                          ),
                        ],
                );
              })
              .toList(growable: false);
          return _countResult(
            result.data.length,
            '个座位',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.libbookBookings:
          final page = query.page <= 0 ? 1 : query.page;
          final limit = query.size.clamp(1, 100);
          final result = await client.libbookBookings(page: page, limit: limit);
          final details = result.data.bookings
              .map((item) {
                final target = item.cancelTarget?.trim();
                final eligibility = _toLibbookActionEligibility(
                  item.cancelEligibility,
                );
                return FeatureDetail(
                  title: item.nameMerge,
                  subtitle: item.areaName,
                  fields: _compactFields(<FeatureField?>[
                    _field('预约 ID', item.id),
                    _field('座位', item.seatNo),
                    _field('日期', item.day),
                    _field('时段', '${item.beginTime}–${item.endTime}'),
                    _field('状态码', item.status?.toString()),
                    _field('状态', item.statusName),
                    _field('可取消', _libbookEligibilityLabel(eligibility)),
                  ]),
                  actions: target == null || target.isEmpty
                      ? const <FeatureAction>[]
                      : <FeatureAction>[
                          LibbookCancelAction(
                            bookingId: target,
                            page: result.data.page,
                            limit: result.data.limit,
                            eligibility: eligibility,
                          ),
                        ],
                );
              })
              .toList(growable: false);
          return _countResult(
            result.data.bookings.length,
            '条预约记录',
            details: details,
            pagination: _pagination(
              page: result.data.page,
              size: result.data.limit,
              total: result.data.total,
            ),
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
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
