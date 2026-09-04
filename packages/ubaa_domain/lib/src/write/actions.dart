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
