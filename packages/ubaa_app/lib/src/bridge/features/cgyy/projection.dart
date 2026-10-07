import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/mapping.dart'
    show bridgeCompactFields, bridgeCountResult, bridgeField, bridgePagination;
part 'cache_projection.dart';
part 'cached_models.dart';
part 'day_projection.dart';

FeatureResult bridgeMapCgyyOrdersResult(
  BridgeCgyyOrdersPage data,
  ConnectionMode resolvedRoute,
) {
  final details = data.content
      .map(
        (item) => FeatureDetail(
          title: item.theme ?? item.siteName ?? '研讨室订单 ${item.id}',
          subtitle: item.venueSpaceName ?? item.venueName,
          presentation: _cgyyOrderPresentation(item),
          readNavigation: item.id <= 0
              ? null
              : FeatureReadNavigation(
                  feature: FeatureId.cgyy,
                  query: FeatureQuery(
                    view: FeatureQueryView.cgyyOrderDetail,
                    orderId: item.id,
                  ),
                ),
          fields: bridgeCompactFields(<FeatureField?>[
            bridgeField('订单编号', '${item.id}'),
            bridgeField(
              '日期',
              item.reservationDateDetail ?? item.reservationDate,
            ),
            bridgeField('开始', item.reservationStartDate),
            bridgeField('结束', item.reservationEndDate),
            bridgeField('用途', item.purposeTypeName),
            item.joinerNum == null
                ? null
                : bridgeField('参与人数', '${item.joinerNum}'),
            bridgeField('订单状态', item.orderStatus?.toString()),
            bridgeField('审核状态', item.checkStatus?.toString()),
            bridgeField(
              '订单状态说明',
              _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
            ),
            bridgeField('审核状态说明', _cgyyCheckStatusText(item.checkStatus)),
          ]),
          actions: _cgyyCancelActions(item),
        ),
      )
      .toList(growable: false);
  return bridgeCountResult(
    data.content.length,
    '条研讨室订单',
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

FeatureResult bridgeMapCgyyOrderDetailResult(
  BridgeCgyyOrder item,
  ConnectionMode resolvedRoute,
) => FeatureResult.success(
  summary: '订单详情',
  details: <FeatureDetail>[
    FeatureDetail(
      title: item.theme ?? item.siteName ?? '研讨室订单 ${item.id}',
      subtitle: item.venueSpaceName ?? item.venueName,
      presentation: _cgyyOrderPresentation(item),
      fields: bridgeCompactFields(<FeatureField?>[
        bridgeField('订单编号', '${item.id}'),
        bridgeField('校区', item.campusName),
        bridgeField('日期', item.reservationDateDetail ?? item.reservationDate),
        bridgeField('开始', item.reservationStartDate),
        bridgeField('结束', item.reservationEndDate),
        bridgeField('用途', item.purposeTypeName),
        item.joinerNum == null
            ? null
            : bridgeField('参与人数', '${item.joinerNum}'),
        bridgeField('订单状态', item.orderStatus?.toString()),
        bridgeField('审核状态', item.checkStatus?.toString()),
        bridgeField(
          '订单状态说明',
          _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
        ),
        bridgeField('审核状态说明', _cgyyCheckStatusText(item.checkStatus)),
      ]),
      actions: _cgyyCancelActions(item),
    ),
  ],
  resolvedRoute: resolvedRoute,
);

List<FeatureAction> _cgyyCancelActions(BridgeCgyyOrder item) {
  if (item.id <= 0) return const <FeatureAction>[];
  return <FeatureAction>[
    CgyyCancelAction(
      orderId: item.id,
      orderStatus: item.orderStatus,
      checkStatus: item.checkStatus,
      targetOrderId: item.cancelTarget?.orderId,
      cancelledTargetOrderId: item.cancelledTarget?.orderId,
      eligibility: _toCgyyActionEligibility(item.cancelEligibility),
    ),
  ];
}

ActionEligibility _toCgyyActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

String? _cgyyCheckStatusText(int? status) => switch (status) {
  1 => '审批通过',
  2 => '待辅导员审批',
  -2 => '辅导员审批驳回',
  3 => '待副书记/副处长审批',
  -3 => '副书记/副处长审批驳回',
  4 => '待宣传部审批',
  -4 => '宣传部审批驳回',
  5 => '待国交处备案',
  -5 => '国交处备案驳回',
  6 => '待教务处审批',
  -6 => '教务处驳回',
  _ => null,
};

String _cgyyOrderStatusText(int? orderStatus, int? checkStatus) {
  if ((checkStatus ?? 0) < 0) {
    return _cgyyCheckStatusText(checkStatus) ?? '审批驳回';
  }
  return switch (orderStatus) {
    2 => '已取消',
    1 when checkStatus == 1 => '审批通过',
    1 when (checkStatus ?? 0) > 0 => '待审批',
    3 => '占用',
    1 => '正常',
    final value => value == null ? '未知' : '未知($value)',
  };
}

CgyyOrderPresentation _cgyyOrderPresentation(BridgeCgyyOrder item) =>
    CgyyOrderPresentation(
      id: item.id,
      venueSiteId: item.venueSiteId,
      reservationDate: item.reservationDate,
      reservationDateDetail: item.reservationDateDetail,
      venueSpaceName: item.venueSpaceName,
      campusName: item.campusName,
      venueName: item.venueName,
      siteName: item.siteName,
      reservationStartDate: item.reservationStartDate,
      reservationEndDate: item.reservationEndDate,
      orderStatus: item.orderStatus,
      checkStatus: item.checkStatus,
      theme: item.theme,
      purposeTypeName: item.purposeTypeName,
      joinerNum: item.joinerNum,
      statusText: _cgyyOrderStatusText(item.orderStatus, item.checkStatus),
      checkStatusText: _cgyyCheckStatusText(item.checkStatus),
    );
