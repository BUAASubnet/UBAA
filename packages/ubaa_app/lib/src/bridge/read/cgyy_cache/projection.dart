part of '../../bridge_backend.dart';

FeatureResult _projectCgyySites(
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
          fields: _compactFields(<FeatureField?>[
            _field('站点 ID', '${item.id}'),
            _field('校区', item.campusName),
            item.seatCount == null ? null : _field('座位数', '${item.seatCount}'),
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
    data.length,
    '个研讨室预约站点',
    details: details,
    resolvedRoute: route,
  );
}

FeatureResult _projectCgyyPurposes(
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
