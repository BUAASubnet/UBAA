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

  /// `/delChosenCourse` 使用的课程本体标识，不是已选记录标识。
  final int courseId;

  @override
  final ActionEligibility eligibility;

  @override
  WriteOperation get operation => WriteOperation.bykcDeselectCourse;
}
