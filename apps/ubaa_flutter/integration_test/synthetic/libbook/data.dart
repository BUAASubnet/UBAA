part of 'backend.dart';

FeatureResult libraryData(FeatureQuery q, String state) {
  final page = q.page <= 0 ? 1 : q.page;
  final size = q.size.clamp(1, 100);
  final day = q.date == null
      ? '2026-09-04'
      : '${q.date!.year}-${q.date!.month.toString().padLeft(2, '0')}-${q.date!.day.toString().padLeft(2, '0')}';
  String label(String value) =>
      state == 'long' ? '$value——跨学科协作学习与讨论空间长名称' : value;
  FeatureDetail item(
    String title,
    FeaturePresentation p, {
    List<FeatureAction> actions = const [],
  }) => FeatureDetail(
    title: title,
    presentation: p,
    actions: actions,
    fields: const [
      FeatureField(label: '馆 ID', value: 'wrong-display-library'),
      FeatureField(label: '分区 ID', value: 'wrong-display-area'),
    ],
  );
  List<FeatureDetail> details;
  switch (q.view) {
    case FeatureQueryView.summary:
      details = [
        for (final id in ['library-a', 'library-b'])
          item(
            '错误展示馆名',
            LibbookLibraryPresentation(
              id: id,
              name: label(id == 'library-a' ? '合成甲馆' : '合成乙馆'),
              freeNum: 3,
              totalNum: 40,
              queryDate: day,
              storeys: [
                LibbookStoreyPresentation(
                  id: '$id-floor-1',
                  name: label('一层'),
                  freeNum: 1,
                  totalNum: 20,
                ),
                LibbookStoreyPresentation(
                  id: '$id-floor-2',
                  name: label('二层'),
                  freeNum: 2,
                  totalNum: 20,
                ),
              ],
            ),
          ),
      ];
    case FeatureQueryView.libbookAreas:
      final parent = q.premisesId!;
      final floor = q.storeyId!;
      details = [
        for (final index in [1, 2])
          item(
            label('安静阅览区 $index'),
            LibbookAreaPresentation(
              id: state == 'map' && index == 1 ? '8' : '$floor-area-$index',
              name: label('安静阅览区 $index'),
              areaName: '合成校区',
              premisesId: state == 'missing-parents'
                  ? ''
                  : state == 'conflicting-parents'
                  ? 'other-library'
                  : parent,
              storeyId: state == 'missing-parents' ? '' : floor,
              freeNum: 1,
              totalNum: 10,
              queryDate: day,
            ),
          ),
      ];
    case FeatureQueryView.libbookAreaDetail:
      details = [
        item(
          label('分区时段'),
          LibbookAreaDetailPresentation(
            id: q.areaId!,
            name: label('分区时段'),
            availableDates: const ['2026-09-04', '2026-09-05'],
            timeSlots: const [
              LibbookTimeSlotPresentation(
                id: 'segment-a',
                start: '08:00',
                end: '10:00',
                label: '上午',
              ),
              LibbookTimeSlotPresentation(
                id: 'segment-b',
                start: '14:00',
                end: '16:00',
                label: '下午',
              ),
            ],
          ),
        ),
      ];
    case FeatureQueryView.libbookSeats:
      details = [
        for (final i in List.generate(state == 'many' ? 42 : 8, (i) => i))
          item(
            '座位 ${i + 1}',
            LibbookSeatPresentation(
              id: 'seat-$i',
              name: label('合成座位 ${i + 1}'),
              number: 'A${i + 1}',
              status: i % 3 == 0
                  ? 1
                  : i % 3 == 1
                  ? 2
                  : null,
              statusName: i % 3 == 0
                  ? '空闲'
                  : i % 3 == 1
                  ? '使用中'
                  : '未知',
              areaId: q.areaId!,
              queryDate: day,
              segment: q.segment!,
              startTime: q.startTime!,
              endTime: q.endTime!,
            ),
            actions: i % 3 == 2
                ? const []
                : [
                    LibbookReserveAction(
                      areaId: q.areaId!,
                      seatId: 'canonical-seat-$i',
                      day: day,
                      segment: q.segment!,
                      startTime: q.startTime!,
                      endTime: q.endTime!,
                      eligibility: i % 3 == 0
                          ? ActionEligibility.allowed
                          : ActionEligibility.denied,
                    ),
                  ],
          ),
      ];
    case FeatureQueryView.libbookBookings:
      final all = [
        for (final index in [1, 2, 3])
          item(
            label('合成甲馆 · 一层'),
            LibbookBookingPresentation(
              id: 'booking-$index',
              name: label('合成甲馆 · 一层'),
              areaName: '安静阅览区',
              seatNumber: 'A$index',
              day: '2026-09-04',
              beginTime: '08:00',
              endTime: '10:00',
              status: index == 3
                  ? null
                  : index == 2
                  ? 6
                  : 1,
              statusName: index == 3
                  ? '未知'
                  : index == 2
                  ? '已结束'
                  : '有效',
            ),
            actions: [
              LibbookCancelAction(
                bookingId: 'canonical-booking-$index',
                page: page,
                limit: size,
                eligibility: index == 1
                    ? ActionEligibility.allowed
                    : index == 2
                    ? ActionEligibility.denied
                    : ActionEligibility.unknown,
              ),
            ],
          ),
      ];
      details = all.skip((page - 1) * size).take(size).toList();
    default:
      throw const BackendException(UbaaErrorCode.invalidInput);
  }
  final pagination = q.view == FeatureQueryView.libbookBookings
      ? FeaturePagination(
          page: page,
          size: size,
          total: 3,
          hasMore: page * size < 3,
        )
      : null;
  if (details.isEmpty) {
    return FeatureResult.empty(
      resolvedRoute: ConnectionMode.direct,
      pagination: pagination,
    );
  }
  return FeatureResult.success(
    summary: '显式合成图书馆数据',
    details: details,
    resolvedRoute: ConnectionMode.direct,
    pagination: pagination,
  );
}
