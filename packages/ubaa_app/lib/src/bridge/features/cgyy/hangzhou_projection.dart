part of 'projection.dart';

/// 杭州校区空间预约站点：日表导航仍留在杭州功能内，不会跳入北京研讨室接口。
FeatureResult bridgeProjectHangzhouCgyySites(
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
                  feature: FeatureId.hangzhouCgyy,
                  query: FeatureQuery(
                    view: FeatureQueryView.cgyyDayInfo,
                    siteId: item.id,
                    date: DateTime.parse(today),
                  ),
                ),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('场馆', item.venueName),
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
    '个杭州场馆',
    details: details,
    resolvedRoute: route,
  );
}

/// 杭州订单的取消入口只排除明确已取消或已结束的订单；能否取消最终由
/// 场馆系统的取消提醒与取消接口决定，界面不推断杭州的取消时限。
List<FeatureAction> _hangzhouCancelActions(BridgeCgyyOrder item, DateTime now) {
  final tradeNo = item.tradeNo?.trim() ?? '';
  final end = DateTime.tryParse(
    (item.reservationEndDate ?? '').trim().replaceFirst(' ', 'T'),
  );
  final cancelled = item.orderStatus == 2 || (item.checkStatus ?? 0) < 0;
  final action = HangzhouCgyyCancelAction(
    tradeNo: tradeNo,
    eligibility: cancelled || (end != null && !now.isBefore(end))
        ? ActionEligibility.denied
        : ActionEligibility.allowed,
  );
  return action.isUsable ? <FeatureAction>[action] : const <FeatureAction>[];
}

/// 杭州校区我的预约列表：不提供详情跳转；可取消的订单附带取消能力。
FeatureResult bridgeMapHangzhouCgyyOrdersResult(
  BridgeCgyyOrdersPage data,
  ConnectionMode resolvedRoute,
) {
  final now = DateTime.now();
  final details = data.content
      .map(
        (item) => FeatureDetail(
          title: item.theme ?? item.siteName ?? '杭州预约 ${item.id}',
          subtitle: item.venueSpaceName ?? item.venueName,
          actions: _hangzhouCancelActions(item, now),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('场馆', item.venueName),
            bridgeField(
              '日期',
              item.reservationDateDetail ?? item.reservationDate,
            ),
            bridgeField('开始', item.reservationStartDate),
            bridgeField('结束', item.reservationEndDate),
            bridgeField('用途', item.purposeTypeName),
            bridgeField(
              '订单状态',
              _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
            ),
            bridgeField('审核状态', _cgyyCheckStatusText(item.checkStatus)),
          ]),
        ),
      )
      .toList(growable: false);
  return bridgeCountResult(
    data.content.length,
    '条杭州预约',
    details: details,
    pagination: bridgePagination(
      page: data.number + 1,
      size: data.size,
      total: data.totalElements,
      totalPages: data.totalPages,
    ),
    resolvedRoute: resolvedRoute,
  );
}
