import 'package:meta/meta.dart';

import '../common/route.dart';
import '../feature/query.dart';

/// 与 bridge 一一对应的封闭写操作枚举。
enum WriteOperation {
  bykcSelectCourse,
  bykcDeselectCourse,
  bykcSignCourse,
  signinPerform,
  libbookReserve,
  libbookCancelBooking,
  ygdkSubmit,
  cgyySubmitReservation,
  cgyyCancelOrder,
  evaluationSubmitCourses,
}

extension WriteOperationText on WriteOperation {
  String get title => switch (this) {
    WriteOperation.bykcSelectCourse => '博雅选课',
    WriteOperation.bykcDeselectCourse => '博雅退选',
    WriteOperation.bykcSignCourse => '博雅签到',
    WriteOperation.signinPerform => '课堂签到',
    WriteOperation.libbookReserve => '图书馆预约',
    WriteOperation.libbookCancelBooking => '取消图书馆预约',
    WriteOperation.ygdkSubmit => '阳光打卡',
    WriteOperation.cgyySubmitReservation => '场馆预约',
    WriteOperation.cgyyCancelOrder => '取消场馆订单',
    WriteOperation.evaluationSubmitCourses => '教学评教',
  };

  bool get isIrreversible => switch (this) {
    WriteOperation.bykcDeselectCourse ||
    WriteOperation.libbookCancelBooking ||
    WriteOperation.cgyyCancelOrder => false,
    _ => true,
  };
}

/// 一次性写入确认意图的安全投影。
@immutable
class WriteIntent {
  const WriteIntent({
    required this.intentId,
    required this.operation,
    required this.targetSummary,
    required this.resolvedRoute,
    required this.warnings,
    required this.expiresAt,
    required this.requestDigest,
    this.readbackQuery,
  });

  final String intentId;
  final WriteOperation operation;
  final String targetSummary;
  final ConnectionMode resolvedRoute;
  final List<String> warnings;
  final DateTime expiresAt;
  final String requestDigest;

  /// 仅供确定成功或结果未知后的只读核对使用，不参与 Bridge commit。
  final FeatureQuery? readbackQuery;

  bool isExpired([DateTime? now]) =>
      !(expiresAt.isAfter(now ?? DateTime.now()));

  WriteIntent withReadbackQuery(FeatureQuery query) => WriteIntent(
    intentId: intentId,
    operation: operation,
    targetSummary: targetSummary,
    resolvedRoute: resolvedRoute,
    warnings: warnings,
    expiresAt: expiresAt,
    requestDigest: requestDigest,
    readbackQuery: query,
  );
}

/// 场馆预约提交后用于只读核对的非敏感订单收据。
///
/// 不包含交易号、手机号、主题、参与人或活动正文；完整订单仍通过受控的
/// 场馆订单详情读取接口获取并按页面白名单投影。
@immutable
class CgyyReservationReceipt {
  const CgyyReservationReceipt({
    required this.orderId,
    this.venueSiteId,
    this.reservationDate,
    this.orderStatus,
  });

  final int orderId;
  final int? venueSiteId;
  final String? reservationDate;
  final int? orderStatus;
}

/// 阳光打卡提交后的安全收据。
///
/// 只包含正整数记录标识；不包含分类、项目、照片、时间、地点或上游原始响应。
@immutable
class YgdkSubmitReceipt {
  const YgdkSubmitReceipt({required this.recordId});

  final int recordId;

  bool get isValid => recordId > 0;
}

/// 写入提交后的安全结果；不携带上游原始正文。
@immutable
class WriteCommitResult {
  const WriteCommitResult({
    required this.operation,
    required this.success,
    required this.message,
    required this.outcomeUnknown,
    this.resolvedRoute,
    this.cgyyReceipt,
    this.ygdkReceipt,
  });

  final WriteOperation operation;
  final bool success;
  final String message;
  final bool outcomeUnknown;
  final ConnectionMode? resolvedRoute;
  final CgyyReservationReceipt? cgyyReceipt;
  final YgdkSubmitReceipt? ygdkReceipt;
}
