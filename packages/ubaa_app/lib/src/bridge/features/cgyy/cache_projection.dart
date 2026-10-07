part of 'projection.dart';

FeatureResult bridgeProjectCgyySites(
  List<BridgeCgyyVenueSite> data,
  ConnectionMode route,
  String today,
) {
  final details = data
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
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('站点 ID', '${item.id}'),
            bridgeField('校区', item.campusName),
            item.seatCount == null
                ? null
                : bridgeField('座位数', '${item.seatCount}'),
            item.reservationSpaceCount == null
                ? null
                : bridgeField('空间数', '${item.reservationSpaceCount}'),
            bridgeField('开放开始', item.openStartDate),
            bridgeField('开放结束', item.openEndDate),
          ]),
        ),
      )
      .toList(growable: false);
  return bridgeCountResult(
    data.length,
    '个研讨室预约站点',
    details: details,
    resolvedRoute: route,
  );
}

FeatureResult bridgeProjectCgyyPurposes(
  BridgeCgyyPurposeTypes data,
  ConnectionMode route,
) {
  final source = data.source == BridgeCgyyPurposeSource.upstream
      ? '上游'
      : '本地冻结回退';
  final details = data.items
      .map(
        (item) => FeatureDetail(
          title: item.name,
          presentation: CgyyPurposePresentation(
            key: item.key,
            name: item.name,
            isStaticFallback:
                data.source == BridgeCgyyPurposeSource.staticFallback,
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
    resolvedRoute: route,
  );
}
