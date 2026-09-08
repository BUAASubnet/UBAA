part of 'backend.dart';

FeatureResult sportsData(
  FeatureQuery query,
  String state, {
  int version = 1,
  bool includeRecords = true,
}) {
  final page = query.page <= 0 ? 1 : query.page;
  final size = query.size.clamp(1, 100);
  final total = state == 'empty'
      ? 0
      : state == 'many'
      ? 42
      : 3;
  final long = state == 'long'
      ? List.filled(3, '与校园运动生活及合成体育项目的较长名称').join(' ')
      : '';
  final all = [
    for (var i = 1; i <= total; i++)
      YgdkRecordPresentation(
        recordId: i,
        itemId: 7,
        itemName: '合成运动记录 $i${version == 1 ? '' : ' 更新$version'}$long',
        startTime: '2026-09-09 08:00',
        endTime: '2026-09-09 09:00',
        place: '合成操场$long',
        imageCount: i == 1 ? 2 : 0,
        isOpen: i == 2,
        state: i == 3 ? 999 : null,
        createdAtLabel: '合成提交时间',
      ),
  ];
  final rows = all.skip((page - 1) * size).take(size).toList();
  if (query.view == FeatureQueryView.ygdkRecords) {
    final pagination = FeaturePagination(
      page: page,
      size: size,
      total: total,
      hasMore: page * size < total,
    );
    return rows.isEmpty
        ? FeatureResult.empty(
            resolvedRoute: ConnectionMode.direct,
            pagination: pagination,
          )
        : FeatureResult.success(
            resolvedRoute: ConnectionMode.direct,
            pagination: pagination,
            details: [
              for (final p in rows)
                FeatureDetail(title: p.itemName!, presentation: p),
            ],
          );
  }
  return FeatureResult.success(
    resolvedRoute: ConnectionMode.direct,
    overview: YgdkOverview(
      termId: 11,
      termName: '合成学期',
      termCount: 0,
      termTarget: state == 'empty' ? null : 16,
      weekCount: 0,
      weekTarget: 3,
      monthCount: null,
      monthTarget: 6,
      dayCount: 0,
      goodCount: 2,
      classifyId: 31,
      classifyName: '合成体育',
      defaultItemId: 7,
      defaultItemName: '合成跑步',
      records: includeRecords
          ? YgdkHomeRecords(
              page: page,
              size: size,
              total: state == 'partial-error' ? null : total,
              hasMore: state == 'partial-error' ? null : page * size < total,
              errorCode: state == 'partial-error'
                  ? UbaaErrorCode.networkError
                  : null,
              content: state == 'partial-error' ? const [] : rows,
            )
          : null,
    ),
    details: [
      for (var i = 0; i < 3; i++)
        FeatureDetail(
          title: '合成运动项目 ${i + 1}$long',
          presentation: YgdkItemPresentation(
            itemId: 7 + i,
            name: '合成运动项目 ${i + 1}$long',
          ),
          actions: i == 2
              ? const []
              : [
                  YgdkSubmitAction(
                    classifyId: 31,
                    itemId: 7 + i,
                    eligibility: ActionEligibility.allowed,
                  ),
                ],
        ),
    ],
  );
}
