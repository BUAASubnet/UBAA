part of 'projection.dart';

FeatureResult bridgeProjectLibbookLibraries(
  List<BridgeLibBookLibrary> data,
  ConnectionMode route,
  String today,
  FeatureQuery query, {
  bool persisted = false,
}) {
  final details = data
      .map(
        (item) => FeatureDetail(
          title: item.name,
          presentation: LibbookLibraryPresentation(
            id: item.id,
            name: item.name,
            freeNum: item.freeNum,
            totalNum: item.totalNum,
            queryDate: today,
            storeys: List.unmodifiable(
              item.storeys.map(
                (floor) => LibbookStoreyPresentation(
                  id: floor.id,
                  name: floor.name,
                  freeNum: floor.freeNum,
                  totalNum: floor.totalNum,
                ),
              ),
            ),
          ),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('馆 ID', item.id),
            bridgeField('空闲座位', '${item.freeNum}'),
            bridgeField('总座位', '${item.totalNum}'),
            bridgeField('楼层数', '${item.storeys.length}'),
          ]),
        ),
      )
      .toList(growable: false);
  return bridgeCountResult(
    data.length,
    '所图书馆',
    details: details,
    resolvedRoute: route,
  );
}

FeatureResult bridgeProjectLibbookAreas(
  List<BridgeLibBookArea> data,
  ConnectionMode route,
  String today,
  FeatureQuery query, {
  bool persisted = false,
}) {
  final details = data
      .map(
        (item) => FeatureDetail(
          title: item.name,
          subtitle: item.areaName,
          presentation: LibbookAreaPresentation(
            id: item.id,
            name: item.name,
            areaName: item.areaName,
            premisesId: item.premisesId,
            storeyId: item.storeyId,
            freeNum: item.freeNum,
            totalNum: item.totalNum,
            queryDate: today,
          ),
          readNavigation: item.id.trim().isEmpty
              ? null
              : FeatureReadNavigation(
                  feature: FeatureId.libbook,
                  query: FeatureQuery(
                    view: FeatureQueryView.libbookAreaDetail,
                    areaId: item.id,
                    date: DateTime.parse(today),
                  ),
                ),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('分区 ID', item.id),
            bridgeField('楼层 ID', item.storeyId),
            bridgeField('空闲座位', '${item.freeNum}'),
            bridgeField('总座位', '${item.totalNum}'),
          ]),
        ),
      )
      .toList(growable: false);
  return bridgeCountResult(
    data.length,
    '个图书馆分区',
    details: details,
    resolvedRoute: route,
  );
}

FeatureResult bridgeProjectLibbookAreaDetail(
  BridgeLibBookAreaDetail data,
  ConnectionMode route,
  String today,
  FeatureQuery query, {
  bool persisted = false,
}) {
  final detail = data;
  return FeatureResult.success(
    summary: '可用日期 ${detail.availableDates.length} 天',
    details: <FeatureDetail>[
      FeatureDetail(
        title: detail.name,
        presentation: LibbookAreaDetailPresentation(
          id: detail.id,
          name: detail.name,
          availableDates: List.unmodifiable(detail.availableDates),
          timeSlots: List.unmodifiable(
            detail.timeSlots.map(
              (slot) => LibbookTimeSlotPresentation(
                id: slot.id,
                start: slot.start,
                end: slot.end,
                label: slot.label,
              ),
            ),
          ),
        ),
        fields: bridgeCompactFields(<FeatureField?>[
          bridgeField('分区 ID', detail.id),
          bridgeField(
            '可用日期',
            detail.availableDates.isEmpty
                ? null
                : detail.availableDates.join('、'),
          ),
          bridgeField(
            '时段',
            detail.timeSlots.isEmpty
                ? null
                : detail.timeSlots.map((slot) => slot.label).join('、'),
          ),
        ]),
      ),
    ],
    resolvedRoute: route,
  );
}

FeatureResult bridgeProjectLibbookSeats(
  List<BridgeLibBookSeat> data,
  ConnectionMode route,
  String today,
  FeatureQuery query, {
  bool persisted = false,
}) {
  final areaId = bridgeRequiredQueryValue(query.areaId, '分区 ID');
  final segment = bridgeRequiredQueryValue(query.segment, '时段');
  final startTime = bridgeRequiredQueryValue(query.startTime, '开始时间');
  final endTime = bridgeRequiredQueryValue(query.endTime, '结束时间');
  final details = data
      .map((item) {
        final target = item.reserveTarget?.trim();
        final eligibility = _toLibbookActionEligibility(
          item.reserveEligibility,
        );
        return FeatureDetail(
          title: item.name,
          subtitle: item.no,
          presentation: LibbookSeatPresentation(
            id: item.id,
            name: item.name,
            number: item.no,
            status: item.status,
            statusName: item.statusName,
            areaId: areaId,
            queryDate: today,
            segment: segment,
            startTime: startTime,
            endTime: endTime,
          ),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('分区 ID', areaId),
            bridgeField('座位 ID', item.id),
            bridgeField('日期', today),
            bridgeField('时段', segment),
            bridgeField('开始时间', startTime),
            bridgeField('结束时间', endTime),
            bridgeField('状态码', item.status?.toString()),
            bridgeField('状态', item.statusName),
            if (!persisted)
              bridgeField('可预约', _libbookEligibilityLabel(eligibility)),
          ]),
          actions: persisted || target == null || target.isEmpty
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
  return bridgeCountResult(
    data.length,
    '个座位',
    details: details,
    resolvedRoute: route,
  );
}

FeatureResult bridgeProjectLibbookBookings(
  BridgeLibBookBookingsPage data,
  ConnectionMode route,
  String today,
  FeatureQuery query, {
  bool persisted = false,
}) {
  final details = data.bookings
      .map((item) {
        final target = item.cancelTarget?.trim();
        final eligibility = _toLibbookActionEligibility(item.cancelEligibility);
        return FeatureDetail(
          title: item.nameMerge,
          subtitle: item.areaName,
          presentation: LibbookBookingPresentation(
            id: item.id,
            name: item.nameMerge,
            areaName: item.areaName,
            seatNumber: item.seatNo,
            day: item.day,
            beginTime: item.beginTime,
            endTime: item.endTime,
            status: item.status,
            statusName: item.statusName,
          ),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('预约 ID', item.id),
            bridgeField('座位', item.seatNo),
            bridgeField('日期', item.day),
            bridgeField('时段', '${item.beginTime}–${item.endTime}'),
            bridgeField('状态码', item.status?.toString()),
            bridgeField('状态', item.statusName),
            if (!persisted)
              bridgeField('可取消', _libbookEligibilityLabel(eligibility)),
          ]),
          actions: persisted || target == null || target.isEmpty
              ? const <FeatureAction>[]
              : <FeatureAction>[
                  LibbookCancelAction(
                    bookingId: target,
                    page: data.page,
                    limit: data.limit,
                    eligibility: eligibility,
                  ),
                ],
        );
      })
      .toList(growable: false);
  return bridgeCountResult(
    data.bookings.length,
    '条预约记录',
    details: details,
    pagination: bridgePagination(
      page: data.page,
      size: data.limit,
      total: data.total,
    ),
    resolvedRoute: route,
  );
}

FeatureResult bridgeProjectLibbookSchedule(
  BridgeLibBookAreaSchedule data,
  ConnectionMode route,
) {
  final detail = data;
  return FeatureResult.success(
    summary: '可用日期 ${detail.days.length} 天',
    details: <FeatureDetail>[
      FeatureDetail(
        title: detail.name,
        presentation: LibbookAreaSchedulePresentation(
          id: detail.id,
          name: detail.name,
          days: List.unmodifiable(
            detail.days.map(
              (day) => LibbookDaySchedulePresentation(
                day: day.day,
                timeSlots: List.unmodifiable(
                  day.timeSlots.map(
                    (slot) => LibbookTimeSlotPresentation(
                      id: slot.id,
                      start: slot.start,
                      end: slot.end,
                      label: slot.label,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        fields: bridgeCompactFields(<FeatureField?>[
          bridgeField('分区 ID', detail.id),
          bridgeField(
            '可用日期',
            detail.days.isEmpty
                ? null
                : detail.days.map((day) => day.day).join('、'),
          ),
          bridgeField(
            '时段',
            detail.days.isEmpty
                ? null
                : detail.days
                      .map(
                        (day) =>
                            '${day.day}：${day.timeSlots.map((slot) => slot.label).join('、')}',
                      )
                      .join('；'),
          ),
        ]),
      ),
    ],
    resolvedRoute: route,
  );
}
