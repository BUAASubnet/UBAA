import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import '../state/state.dart' show ControllerState;

mixin ControllerReadbackDispatch on ControllerState {
  @internal
  Future<void> internalRefreshAfterWrite(
    WriteOperation operation, [
    FeatureQuery? readbackQuery,
  ]) {
    if (operation == WriteOperation.libbookReserve ||
        operation == WriteOperation.libbookCancelBooking) {
      if (internalBackend is FeatureQueryBackend) {
        internalReadCacheEpoch++;
        return internalRefreshFeatureQuery(
          FeatureId.libbook,
          readbackQuery ??
              const FeatureQuery(view: FeatureQueryView.libbookBookings),
          writeReadback: true,
        );
      }
    }
    if (operation == WriteOperation.cgyySubmitReservation) {
      // 订单列表是场馆写入的唯一稳定核对入口；若后端不支持筛选查询，
      // 保留旧的领域刷新兼容路径，不伪造核对成功。
      if (internalBackend is FeatureQueryBackend) {
        internalReadCacheEpoch++;
        return internalRefreshFeatureQuery(
          FeatureId.cgyy,
          const FeatureQuery(view: FeatureQueryView.cgyyOrders),
          writeReadback: true,
        );
      }
    }
    if (operation == WriteOperation.cgyyCancelOrder) {
      // 场馆取消必须由 verifyCgyyCancellation 独占执行列表+详情双回读；
      // 此通用入口不做单列表降级，也不会触发写入重试。
      return Future<void>.value();
    }
    if (operation == WriteOperation.ygdkSubmit) {
      // 阳光打卡必须由 refreshYgdkAfterWrite 使用 intent 的原路线读取
      // 概览和首页记录；通用刷新不得降级为 Auto 路线。
      return Future<void>.value();
    }
    if (operation == WriteOperation.evaluationSubmitCourses) {
      // 评教必须使用 intent 原路线回读；通用刷新不得重新执行 Auto。
      return Future<void>.value();
    }
    final feature = switch (operation) {
      WriteOperation.bykcSelectCourse ||
      WriteOperation.bykcDeselectCourse ||
      WriteOperation.bykcSignCourse => FeatureId.bykc,
      WriteOperation.signinPerform => FeatureId.signin,
      WriteOperation.libbookReserve ||
      WriteOperation.libbookCancelBooking => FeatureId.libbook,
      WriteOperation.ygdkSubmit => FeatureId.ygdk,
      WriteOperation.cgyySubmitReservation ||
      WriteOperation.cgyyCancelOrder => FeatureId.cgyy,
      WriteOperation.evaluationSubmitCourses => throw StateError(
        '评教使用调用方固定路线回读',
      ),
    };
    return internalRefreshHome(only: <FeatureId>[feature], writeReadback: true);
  }
}
