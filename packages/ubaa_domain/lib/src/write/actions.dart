import 'package:meta/meta.dart';

import 'intent.dart';

/// Core 对当前目标写入资格的封闭判定。
///
/// [unknown] 与 action 缺失都必须在消费端按拒绝处理，不得由
/// 展示文案或其它可选字段推测。
enum ActionEligibility { allowed, denied, unknown }

/// 详情中可被界面精确消费的 typed 写入能力。
@immutable
abstract class FeatureAction {
  const FeatureAction();

  WriteOperation get operation;
  ActionEligibility get eligibility;
}

/// 单门博雅课程的选课能力。
@immutable
class BykcSelectAction extends FeatureAction {
  const BykcSelectAction({required this.courseId, required this.eligibility});

  final int courseId;

  @override
  final ActionEligibility eligibility;

  @override
  WriteOperation get operation => WriteOperation.bykcSelectCourse;
}

/// 单门博雅课程的退选能力。
@immutable
class BykcDeselectAction extends FeatureAction {
  const BykcDeselectAction({required this.courseId, required this.eligibility});

  /// Core 写入合同使用的课程本体标识，不是已选记录标识。
  final int courseId;

  @override
  final ActionEligibility eligibility;

  @override
  WriteOperation get operation => WriteOperation.bykcDeselectCourse;
}

/// 博雅课程签到动作的封闭类型。
enum BykcSignKind {
  signIn(1),
  signOut(2);

  const BykcSignKind(this.signType);

  /// Core 写入合同中的签到类型：`1` 为签到，`2` 为签退。
  final int signType;
}

/// 单门已选博雅课程的签到或签退能力。
@immutable
class BykcSignAction extends FeatureAction {
  const BykcSignAction({
    required this.courseId,
    required this.kind,
    required this.eligibility,
    required this.requiresCoordinates,
  });

  /// Core 写入合同使用的课程本体标识，不是已选记录标识。
  final int courseId;

  final BykcSignKind kind;

  /// `true` 表示 Core 无法仅靠完整的正半径签到范围生成坐标，宿主必须在
  /// prepare 前取得一次前台位置；该字段只来自读取 DTO，不由展示文案推测。
  final bool requiresCoordinates;

  int get signType => kind.signType;

  @override
  final ActionEligibility eligibility;

  @override
  WriteOperation get operation => WriteOperation.bykcSignCourse;
}

/// 单门课堂签到的 Core 已核对安排目标。
@immutable
class SigninPerformAction extends FeatureAction {
  const SigninPerformAction({
    required this.scheduleId,
    required this.eligibility,
  });

  /// Core 从今日课程响应核对出的课程安排标识。
  final String scheduleId;

  @override
  final ActionEligibility eligibility;

  @override
  WriteOperation get operation => WriteOperation.signinPerform;
}

/// 单个图书馆座位的 Core 已核对预约目标。
///
/// 六个目标字段由读取查询上下文和 Bridge 的 typed 座位目标共同组成；消费端不得
/// 从 `FeatureDetail.fields` 的展示文案重建这些值。
@immutable
class LibbookReserveAction extends FeatureAction {
  const LibbookReserveAction({
    required this.areaId,
    required this.seatId,
    required this.day,
    required this.segment,
    required this.startTime,
    required this.endTime,
    required this.eligibility,
  });

  final String areaId;
  final String seatId;
  final String day;
  final String segment;
  final String startTime;
  final String endTime;

  @override
  final ActionEligibility eligibility;

  @override
  WriteOperation get operation => WriteOperation.libbookReserve;
}

/// 单个场馆时段的 Core 已核对预约目标。
///
/// [timeOrdinal] 是时段在当次 fresh day-info 中的顺序，只用于校验
/// 两个选择是否相邻；最终上游表单不携带该字段。
@immutable
class CgyyReserveAction extends FeatureAction {
  const CgyyReserveAction({
    required this.venueSiteId,
    required this.reservationDate,
    required this.spaceId,
    required this.timeId,
    required this.venueSpaceGroupId,
    required this.timeOrdinal,
    required this.eligibility,
  });

  final int venueSiteId;
  final String reservationDate;
  final int spaceId;
  final int timeId;
  final int? venueSpaceGroupId;
  final int timeOrdinal;

  @override
  final ActionEligibility eligibility;

  @override
  WriteOperation get operation => WriteOperation.cgyySubmitReservation;
}

/// 单条场馆订单的 typed 取消能力。
///
/// [orderId]、[orderStatus] 和 [checkStatus] 仅用于兼容展示；只有
/// [eligibility] 为 [ActionEligibility.allowed] 时 Core 才会给出
/// canonical [targetOrderId]，只有 strict 已取消时才给出
/// [cancelledTargetOrderId]。界面和 App 层不得从展示值重建证明。
@immutable
class CgyyCancelAction extends FeatureAction {
  const CgyyCancelAction({
    required this.orderId,
    required this.orderStatus,
    required this.checkStatus,
    required this.targetOrderId,
    this.cancelledTargetOrderId,
    required this.eligibility,
  });

  final int orderId;
  final int? orderStatus;
  final int? checkStatus;
  final int? targetOrderId;

  /// Core 仅在 strict 正整数身份且 strict 已取消状态同时成立时提供。
  final int? cancelledTargetOrderId;

  @override
  final ActionEligibility eligibility;

  /// 是否携带可直接交给写入边界的 canonical 正整数目标。
  bool get hasCanonicalTarget =>
      eligibility == ActionEligibility.allowed &&
      orderId > 0 &&
      targetOrderId == orderId;

  /// 当前 action 是否构成指定订单已经取消的 strict 只读证明。
  bool confirmsCancellationOf(int expectedOrderId) =>
      expectedOrderId > 0 &&
      orderId == expectedOrderId &&
      orderStatus == 2 &&
      cancelledTargetOrderId == expectedOrderId;

  @override
  WriteOperation get operation => WriteOperation.cgyyCancelOrder;
}

/// 单个阳光打卡项目的 Core 已核对提交目标。
///
/// 分类和项目标识必须同时为正整数，且 [eligibility] 必须为
/// [ActionEligibility.allowed]，才能进入 prepare。展示文案不得补齐或
/// 覆盖任一目标字段。
@immutable
class YgdkSubmitAction extends FeatureAction {
  const YgdkSubmitAction({
    required this.classifyId,
    required this.itemId,
    required this.eligibility,
  });

  final int classifyId;
  final int itemId;

  @override
  final ActionEligibility eligibility;

  bool get hasCanonicalTarget =>
      eligibility == ActionEligibility.allowed && classifyId > 0 && itemId > 0;

  @override
  WriteOperation get operation => WriteOperation.ygdkSubmit;
}

/// 单条图书馆预约记录的 Core 已核对取消目标。
///
/// [page] 与 [limit] 只限定 prepare、commit 和写后刷新使用的同一预约页；
/// 最终上游取消正文仍只包含 [bookingId]。
@immutable
class LibbookCancelAction extends FeatureAction {
  const LibbookCancelAction({
    required this.bookingId,
    required this.page,
    required this.limit,
    required this.eligibility,
  });

  final String bookingId;
  final int page;
  final int limit;

  @override
  final ActionEligibility eligibility;

  @override
  WriteOperation get operation => WriteOperation.libbookCancelBooking;
}
