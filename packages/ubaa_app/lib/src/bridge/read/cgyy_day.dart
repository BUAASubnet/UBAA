part of '../bridge_backend.dart';

FeatureResult _mapCgyyDayInfo(BridgeCgyyDayInfo data, ConnectionMode route) {
  final details = <FeatureDetail>[
    FeatureDetail(
      title: '预约时间',
      presentation: CgyyDayPresentation(
        venueSiteId: data.venueSiteId,
        reservationDate: data.reservationDate,
        availableDates: List.unmodifiable(data.availableDates),
        timeSlots: List.unmodifiable(
          data.timeSlots.map(
            (time) => CgyyTimePresentation(
              id: time.id,
              beginTime: time.beginTime,
              endTime: time.endTime,
              label: time.label,
            ),
          ),
        ),
        spaces: List.unmodifiable(
          data.spaces.map(
            (space) => CgyySpacePresentation(
              spaceId: space.spaceId,
              spaceName: space.spaceName,
              venueSiteId: space.venueSiteId,
              venueSpaceGroupId: space.venueSpaceGroupId,
            ),
          ),
        ),
        reservationTotalNum: data.reservationTotalNum,
      ),
      fields: _compactFields([
        _field('站点 ID', '${data.venueSiteId}'),
        _field('日期', data.reservationDate),
        _field('可选日期', data.availableDates.join('、')),
      ]),
    ),
  ];
  for (final space in data.spaces) {
    for (final slot in space.slots) {
      final matching = data.timeSlots
          .where((time) => time.id == slot.timeId)
          .toList();
      // 重复编号没有唯一时间含义，保留原槽位但不借用第一项标签。
      final time = matching.length == 1 ? matching.single : null;
      final eligibility = _toCgyyActionEligibility(slot.reservationEligibility);
      final target = slot.reservationTarget;
      final usable =
          eligibility == ActionEligibility.allowed &&
          target != null &&
          target.venueSiteId > 0 &&
          target.reservationDate.trim().isNotEmpty &&
          target.spaceId > 0 &&
          target.timeId > 0 &&
          target.timeOrdinal >= 0 &&
          (target.venueSpaceGroupId == null || target.venueSpaceGroupId! > 0);
      details.add(
        FeatureDetail(
          title: '${space.spaceName} ${time?.label ?? '时段 ${slot.timeId}'}',
          presentation: CgyySlotPresentation(
            venueSiteId: space.venueSiteId,
            reservationDate: data.reservationDate,
            spaceId: space.spaceId,
            spaceName: space.spaceName,
            venueSpaceGroupId: space.venueSpaceGroupId,
            timeId: slot.timeId,
            reservationStatus: slot.reservationStatus,
            beginTime: time?.beginTime,
            endTime: time?.endTime,
            timeLabel: time?.label,
            startDate: slot.startDate,
            endDate: slot.endDate,
          ),
          fields: _compactFields([
            _field('站点 ID', '${data.venueSiteId}'),
            _field('日期', data.reservationDate),
            _field('空间 ID', '${space.spaceId}'),
            _field('空间组 ID', space.venueSpaceGroupId?.toString()),
            _field('时段 ID', '${slot.timeId}'),
            _field('开始时间', time?.beginTime),
            _field('结束时间', time?.endTime),
            _field('状态码', slot.reservationStatus?.toString()),
            _field(
              '可预约',
              usable
                  ? '是'
                  : eligibility == ActionEligibility.denied
                  ? '否'
                  : '无法确认',
            ),
          ]),
          actions: [
            if (usable)
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
  // 无可预约项仍有日期和空间信息，不能归为整个页面空结果。
  return FeatureResult.success(
    summary: '${data.spaces.length} 个研讨室 · ${details.length - 1} 个时段',
    details: details,
    resolvedRoute: route,
  );
}
