part of '../presentation.dart';

final class SigninPresentation extends FeaturePresentation {
  const SigninPresentation({
    required this.courseId,
    required this.classBeginTime,
    required this.classEndTime,
    this.signStatus,
    this.actionTarget,
  });
  final String courseId;

  /// 当次在线 DTO 的目标，只用于核对同次 typed action。缓存不保存。
  final String? actionTarget;
  final String classBeginTime;
  final String classEndTime;
  final int? signStatus;
}
