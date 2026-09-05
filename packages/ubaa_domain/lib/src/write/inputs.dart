import 'package:meta/meta.dart';

import 'actions.dart';

/// 阳光打卡照片的内存输入；不得写入会话、日志或持久化配置。
@immutable
class YgdkPhotoInput {
  const YgdkPhotoInput({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final List<int> bytes;
  final String fileName;
  final String mimeType;
}

/// 阳光打卡 typed 提交参数。所有字段均只在一次写意图生命周期内存在。
@immutable
class YgdkSubmitInput {
  const YgdkSubmitInput({
    required this.action,
    required this.startTime,
    required this.endTime,
    this.place,
    required this.shareToSquare,
    required this.photo,
  });

  /// 只能来自当次读取结果的 Core typed action。
  final YgdkSubmitAction action;
  final String startTime;
  final String endTime;
  final String? place;
  final bool shareToSquare;
  final YgdkPhotoInput photo;
}

/// 场馆预约 typed 提交参数；目标只能来自读取结果的 [actions]。
///
/// 站点、日期、空间和时段不再提供 primitive 覆盖入口；验证码材料
/// 仍由 Core/受控挑战流程持有。
@immutable
class CgyySubmitInput {
  const CgyySubmitInput({
    required this.actions,
    required this.phone,
    required this.theme,
    required this.purposeType,
    required this.joinerNum,
    required this.activityContent,
    required this.joiners,
    required this.isPhilosophySocialSciences,
    required this.isOffSchoolJoiner,
  });

  final List<CgyyReserveAction> actions;
  final String phone;
  final String theme;
  final int purposeType;
  final int joinerNum;
  final String activityContent;
  final String joiners;
  final bool isPhilosophySocialSciences;
  final bool isOffSchoolJoiner;
}
