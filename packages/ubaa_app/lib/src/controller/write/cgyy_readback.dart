import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import '../state/state.dart' show ControllerState;

/// 场馆取消后依次读取订单列表与同 ID 详情，不重试写请求。
///
/// 两个读取必须在 intent 的实际路线上都返回唯一 typed 订单，且携带
/// Core 严格派生的同 ID 已取消证明，才可标记为已核对。任一读取为空、
/// 失败、路线不同或证明缺失都返回 `false`。
Future<bool> controllerVerifyCgyyCancellation(
  ControllerState controller, {
  required int orderId,
  required ConnectionMode expectedRoute,
}) async {
  if (controller.internalDisposed ||
      orderId <= 0 ||
      controller.internalBackend is! CgyyCancellationReadbackBackend) {
    return false;
  }
  final backend = controller.internalBackend as CgyyCancellationReadbackBackend;
  // 本次回读成为最新的场馆刷新；若期间发生新的查询，generation 会阻止
  // 这次较旧的列表覆盖 UI，但 proof 始终只使用下方局部结果。
  final lifecycleEpoch = controller.internalLifecycleEpoch;
  final generation = controller.internalNextFeatureGeneration(FeatureId.cgyy);
  controller.internalCacheLifecycle.invalidateReads();
  controller.internalNotify();
  if (!controller.internalIsFeatureLoadCurrent(
    FeatureId.cgyy,
    generation,
    lifecycleEpoch,
    null,
  ))
    return false;

  FeatureResult? listResult;
  FeatureResult? detailResult;
  try {
    listResult = await backend.loadCgyyOrdersOnRoute(
      route: expectedRoute,
      page: 0,
      size: 20,
    );
    if (listResult.error == null &&
        listResult.resolvedRoute == expectedRoute &&
        controller.internalApplyFeatureResultIfCurrent(
          FeatureId.cgyy,
          listResult,
          generation,
          lifecycleEpoch,
          readContext: FeatureReadContext(
            query: const FeatureQuery(
              view: FeatureQueryView.cgyyOrders,
              page: 0,
              size: 20,
            ),
            requestRevision: generation,
          ),
        )) {
      controller.internalNotify();
    }
  } on Object catch (error, stackTrace) {
    // 列表读取失败仅表示未核对，仍继续独立读取详情。
    if (controller.internalIsFeatureLoadCurrent(
      FeatureId.cgyy,
      generation,
      lifecycleEpoch,
      null,
    )) {
      controller.internalRecordFailure(
        error,
        DiagnosticOperation.readback,
        stackTrace: stackTrace,
        feature: FeatureId.cgyy,
      );
    }
  }
  if (controller.internalDisposed ||
      lifecycleEpoch != controller.internalLifecycleEpoch) {
    return false;
  }
  try {
    detailResult = await backend.loadCgyyOrderDetailOnRoute(
      route: expectedRoute,
      orderId: orderId,
    );
  } on Object catch (error, stackTrace) {
    // 详情读取失败仅表示未核对，不得触发写入重试。
    if (controller.internalIsFeatureLoadCurrent(
      FeatureId.cgyy,
      generation,
      lifecycleEpoch,
      null,
    )) {
      controller.internalRecordFailure(
        error,
        DiagnosticOperation.readback,
        stackTrace: stackTrace,
        feature: FeatureId.cgyy,
      );
    }
  }

  if (listResult == null ||
      listResult.error != null ||
      listResult.isEmpty ||
      detailResult == null ||
      detailResult.error != null ||
      detailResult.isEmpty ||
      listResult.resolvedRoute != expectedRoute ||
      detailResult.resolvedRoute != expectedRoute) {
    return false;
  }
  final listAction = controllerUniqueCgyyCancelAction(
    listResult.details,
    orderId,
  );
  final detailAction = controllerUniqueCgyyCancelAction(
    detailResult.details,
    orderId,
  );
  return listAction?.confirmsCancellationOf(orderId) == true &&
      detailAction?.confirmsCancellationOf(orderId) == true;
}

CgyyCancelAction? controllerUniqueCgyyCancelAction(
  List<FeatureDetail> details,
  int orderId,
) {
  final matches = <CgyyCancelAction>[
    for (final detail in details)
      for (final action in detail.actions)
        if (action is CgyyCancelAction && action.orderId == orderId) action,
  ];
  return matches.length == 1 ? matches.single : null;
}
