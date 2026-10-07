import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/mapping.dart'
    show bridgeCompactFields, bridgeCountResult, bridgeField, bridgePagination;
part 'projection_home.dart';

FeatureResult bridgeMapYgdkOverviewResult(
  BridgeYgdkOverview data,
  ConnectionMode resolvedRoute, {
  YgdkHomeRecords? records,
}) {
  final itemIdCounts = <int, int>{};
  for (final item in data.items) {
    itemIdCounts.update(item.itemId, (count) => count + 1, ifAbsent: () => 1);
  }
  final details = data.items
      .map(
        (item) => FeatureDetail(
          title: item.name,
          presentation: YgdkItemPresentation(
            itemId: item.itemId,
            name: item.name,
            kind: item.kind,
            sort: item.sort,
          ),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('项目编号', '${item.itemId}'),
            item.kind == null ? null : bridgeField('类型', '${item.kind}'),
          ]),
          actions: _ygdkSubmitActions(data, item, itemIdCounts),
        ),
      )
      .toList(growable: false);
  final summary = data.summary.termTarget == null
      ? '已打卡 ${data.summary.termCount} 次'
      : '学期进度 ${data.summary.termCount}/${data.summary.termTarget}';
  return FeatureResult.success(
    summary: summary,
    overview: YgdkOverview(
      termId: data.summary.termId,
      termName: data.summary.termName,
      termCount: data.summary.termCount,
      termTarget: data.summary.termTarget,
      weekCount: data.summary.weekCount,
      weekTarget: data.summary.weekTarget,
      monthCount: data.summary.monthCount,
      monthTarget: data.summary.monthTarget,
      dayCount: data.summary.dayCount,
      goodCount: data.summary.goodCount,
      classifyId: data.classifyId,
      classifyName: data.classifyName,
      defaultItemId: data.defaultItemId,
      defaultItemName: data.defaultItemName,
      records: records,
    ),
    details: details,
    resolvedRoute: resolvedRoute,
  );
}

FeatureResult bridgeMapYgdkRecordsResult(
  BridgeYgdkRecordsPage data,
  ConnectionMode resolvedRoute,
) {
  final details = data.content
      .map(
        (item) => FeatureDetail(
          title: item.itemName ?? '打卡记录 ${item.recordId}',
          subtitle: item.createdAtLabel ?? item.createdAt,
          presentation: _ygdkRecordPresentation(item),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('记录编号', '${item.recordId}'),
            bridgeField('开始时间', item.startTime),
            bridgeField('结束时间', item.endTime),
            bridgeField('地点', item.place),
            bridgeField('公开状态', item.isOpen ? '公开' : '不公开'),
            bridgeField('图片数量', '${item.imageCount}'),
          ]),
        ),
      )
      .toList(growable: false);
  return bridgeCountResult(
    data.content.length,
    '条打卡记录',
    details: details,
    pagination: bridgePagination(
      page: data.page,
      size: data.size,
      total: data.total,
      hasMore: data.hasMore,
    ),
    resolvedRoute: resolvedRoute,
  );
}

List<FeatureAction> _ygdkSubmitActions(
  BridgeYgdkOverview overview,
  BridgeYgdkItem item,
  Map<int, int> itemIdCounts,
) {
  if (overview.classifyId <= 0 ||
      overview.classifyName.trim().isEmpty ||
      item.itemId <= 0 ||
      item.name.trim().isEmpty ||
      itemIdCounts[item.itemId] != 1) {
    return const <FeatureAction>[];
  }
  final target = item.submitTarget;
  if (item.submitEligibility != BridgeActionEligibility.allowed ||
      target == null ||
      target.classifyId != overview.classifyId ||
      target.itemId != item.itemId ||
      target.classifyId <= 0 ||
      target.itemId <= 0) {
    return const <FeatureAction>[];
  }
  return <FeatureAction>[
    YgdkSubmitAction(
      classifyId: target.classifyId,
      itemId: target.itemId,
      eligibility: _toYgdkActionEligibility(item.submitEligibility),
    ),
  ];
}

ActionEligibility _toYgdkActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

YgdkRecordPresentation _ygdkRecordPresentation(BridgeYgdkRecord item) =>
    YgdkRecordPresentation(
      recordId: item.recordId,
      itemId: item.itemId,
      itemName: item.itemName,
      startTime: item.startTime,
      endTime: item.endTime,
      place: item.place,
      imageCount: item.imageCount,
      isOpen: item.isOpen,
      state: item.state,
      createdAt: item.createdAt,
      createdAtLabel: item.createdAtLabel,
    );
