part of 'backend.dart';

FeatureResult roomData(FeatureQuery query, String state) {
  final suffix = state == 'long' ? '——跨学科协作学习与讨论空间长名称' : '';
  final date = query.date?.toIso8601String().split('T').first ?? '2026-09-04';
  final site = query.siteId ?? 7;
  switch (query.view) {
    case FeatureQueryView.summary:
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          for (final id in [7, 17])
            FeatureDetail(
              title: '兼容站点',
              fields: const [FeatureField(label: '站点 ID', value: '999')],
              presentation: CgyySitePresentation(
                id: id,
                siteName: '一层$suffix',
                venueName: '${id == 7 ? '合成甲楼' : '合成乙楼'}$suffix',
                campusName: id == 7 ? '学院路校区' : '沙河校区',
                seatCount: 40,
                queryDate: date,
              ),
            ),
        ],
      );
    case FeatureQueryView.cgyyDayInfo:
      final times = [
        for (final entry in [
          (9, '08:00', '09:00'),
          (3, '09:00', '10:00'),
          (8, '10:00', '11:00'),
          (12, '11:00', '12:00'),
        ])
          CgyyTimePresentation(
            id: entry.$1,
            beginTime: entry.$2,
            endTime: entry.$3,
            label: '${entry.$2}–${entry.$3}',
          ),
      ];
      final rooms = List.generate(
        state == 'many' ? 42 : 3,
        (i) => CgyySpacePresentation(
          spaceId: i + 4,
          spaceName: i == 2 ? '无时段房间$suffix' : '合成研讨室 ${i + 1}$suffix',
          venueSiteId: site,
          venueSpaceGroupId: 2,
        ),
      );
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '预约时间',
            presentation: CgyyDayPresentation(
              venueSiteId: site,
              reservationDate: date,
              availableDates: const ['2026-09-04', '2026-09-05'],
              timeSlots: times,
              spaces: rooms,
              reservationTotalNum: 8,
            ),
          ),
          for (var i = 0; i < rooms.length; i++)
            if (i != 2)
              for (var t = 0; t < times.length; t++)
                FeatureDetail(
                  title: '${rooms[i].spaceName} ${times[t].label}',
                  fields: [
                    FeatureField(
                      label: '状态',
                      value: t == 2
                          ? '资格未知'
                          : t == 3
                          ? '不可预约'
                          : '可预约',
                    ),
                  ],
                  presentation: CgyySlotPresentation(
                    venueSiteId: site,
                    reservationDate: date,
                    spaceId: rooms[i].spaceId,
                    spaceName: rooms[i].spaceName,
                    venueSpaceGroupId: 2,
                    timeId: times[t].id,
                    beginTime: times[t].beginTime,
                    endTime: times[t].endTime,
                    timeLabel: times[t].label,
                    reservationStatus: t == 2 ? null : 1,
                  ),
                  actions: [
                    if (t < 2)
                      CgyyReserveAction(
                        venueSiteId: site,
                        reservationDate: date,
                        spaceId: rooms[i].spaceId,
                        timeId: times[t].id,
                        venueSpaceGroupId: 2,
                        timeOrdinal: t,
                        eligibility: ActionEligibility.allowed,
                      ),
                  ],
                ),
        ],
      );
    case FeatureQueryView.cgyyOrders:
    case FeatureQueryView.cgyyOrderDetail:
      final all = [
        for (final id in [101, 102, 103])
          FeatureDetail(
            title: '合成订单',
            presentation: CgyyOrderPresentation(
              id: id,
              venueSiteId: 7,
              reservationDate: '2026-09-04',
              reservationDateDetail: '2026-09-04 08:00–10:00',
              venueName: '合成甲楼$suffix',
              venueSpaceName: '合成研讨室 1$suffix',
              theme: '课程讨论$suffix',
              purposeTypeName: '学习类',
              orderStatus: id == 102 ? 2 : 1,
              checkStatus: id == 103 ? null : 1,
              statusText: id == 102
                  ? '已取消'
                  : id == 103
                  ? '未知'
                  : '审批通过',
            ),
            fields: [
              FeatureField(label: '订单编号', value: '$id'),
              const FeatureField(label: '参与人数', value: '2'),
            ],
            readNavigation: query.view == FeatureQueryView.cgyyOrderDetail
                ? null
                : FeatureReadNavigation(
                    feature: FeatureId.cgyy,
                    query: FeatureQuery(
                      view: FeatureQueryView.cgyyOrderDetail,
                      orderId: id,
                    ),
                  ),
            actions: [
              CgyyCancelAction(
                orderId: id,
                orderStatus: id == 102 ? 2 : 1,
                checkStatus: id == 103 ? null : 1,
                targetOrderId: id == 101 ? id : null,
                cancelledTargetOrderId: id == 102 ? id : null,
                eligibility: id == 101
                    ? ActionEligibility.allowed
                    : id == 102
                    ? ActionEligibility.denied
                    : ActionEligibility.unknown,
              ),
            ],
          ),
      ];
      if (query.view == FeatureQueryView.cgyyOrderDetail) {
        return FeatureResult.success(
          resolvedRoute: ConnectionMode.direct,
          details: all
              .where(
                (d) =>
                    (d.presentation! as CgyyOrderPresentation).id ==
                    query.orderId,
              )
              .toList(),
        );
      }
      final page = query.page <= 0 ? 1 : query.page,
          size = query.size.clamp(1, 100);
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: all.skip((page - 1) * size).take(size).toList(),
        pagination: FeaturePagination(
          page: page,
          size: size,
          total: 3,
          totalPages: (3 / size).ceil(),
          hasMore: page * size < 3,
        ),
      );
    case FeatureQueryView.cgyyPurposeTypes:
      return const FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '学习类',
            presentation: CgyyPurposePresentation(
              key: 1,
              name: '学习类',
              isStaticFallback: true,
            ),
            fields: [FeatureField(label: '来源', value: '本地冻结回退')],
          ),
        ],
      );
    case FeatureQueryView.cgyyLockCode:
      return const FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '门锁状态',
            presentation: CgyyLockPresentation(available: false),
            fields: [FeatureField(label: '可用', value: '否')],
          ),
        ],
      );
    default:
      throw StateError('合成研讨室不支持该视图');
  }
}
