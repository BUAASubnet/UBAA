import 'package:meta/meta.dart';

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
    this.itemId,
    this.startTime,
    this.endTime,
    this.place,
    this.shareToSquare,
    this.photo,
  });

  final int? itemId;
  final String? startTime;
  final String? endTime;
  final String? place;
  final bool? shareToSquare;
  final YgdkPhotoInput? photo;
}

/// 场馆预约中由读取结果选择的空间及时段。
@immutable
class CgyyReservationSelectionInput {
  const CgyyReservationSelectionInput({
    required this.spaceId,
    required this.timeId,
    this.venueSpaceGroupId,
  });

  final int spaceId;
  final int timeId;
  final int? venueSpaceGroupId;
}

/// 场馆预约 typed 提交参数；验证码材料仍由 Core/受控挑战流程持有。
@immutable
class CgyySubmitInput {
  const CgyySubmitInput({
    required this.venueSiteId,
    required this.reservationDate,
    required this.selections,
    required this.phone,
    required this.theme,
    required this.purposeType,
    required this.joinerNum,
    required this.activityContent,
    required this.joiners,
    required this.isPhilosophySocialSciences,
    required this.isOffSchoolJoiner,
  });

  final int venueSiteId;
  final String reservationDate;
  final List<CgyyReservationSelectionInput> selections;
  final String phone;
  final String theme;
  final int purposeType;
  final int joinerNum;
  final String activityContent;
  final String joiners;
  final bool isPhilosophySocialSciences;
  final bool isOffSchoolJoiner;
}

/// 教学评教提交所需的冻结课程字段；不包含题目答案或任意 raw payload。
@immutable
class EvaluationCourseInput {
  const EvaluationCourseInput({
    required this.id,
    required this.kcmc,
    required this.bpmc,
    this.isEvaluated = false,
    required this.rwid,
    required this.wjid,
    required this.kcdm,
    this.bpdm,
    this.pjrdm,
    this.pjrmc,
    this.xnxq,
    required this.msid,
    this.zdmc,
    this.ypjcs,
    this.xypjcs,
    this.sxz,
    this.rwh,
    this.xn,
    this.xq,
    this.pjlxid,
    this.sfksqbpj,
    this.yxsfktjst,
  });

  final String id;
  final String kcmc;
  final String bpmc;
  final bool isEvaluated;
  final String rwid;
  final String wjid;
  final String kcdm;
  final String? bpdm;
  final String? pjrdm;
  final String? pjrmc;
  final String? xnxq;
  final String msid;
  final String? zdmc;
  final int? ypjcs;
  final int? xypjcs;
  final String? sxz;
  final String? rwh;
  final String? xn;
  final String? xq;
  final String? pjlxid;
  final String? sfksqbpj;
  final String? yxsfktjst;
}
