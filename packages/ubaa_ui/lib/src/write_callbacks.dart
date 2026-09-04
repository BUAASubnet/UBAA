import 'package:ubaa_domain/ubaa_domain.dart';

/// 博雅签到/签退准备回调；保留读取层给出的完整 typed action。
typedef BykcSignPreparer = Future<WriteIntent> Function(BykcSignAction action);

/// 博雅签到/签退启动回调；不得把是否需要调用方坐标降级为展示字段推测。
typedef BykcSignStarter = Future<void> Function(BykcSignAction action);

/// 释放尚未提交的一次性意图；成功表示 Bridge 已移除对应 pending 状态。
typedef WriteIntentDiscarder = Future<void> Function(String intentId);

/// 图书馆预约准备回调。
typedef LibbookReservePreparer =
    Future<WriteIntent> Function({
      required String areaId,
      required String seatId,
      required String day,
      required String segment,
      required String startTime,
      required String endTime,
    });

/// 图书馆预约启动回调。
typedef LibbookReserveStarter =
    Future<void> Function({
      required String areaId,
      required String seatId,
      required String day,
      required String segment,
      required String startTime,
      required String endTime,
    });

/// 教学评教准备回调。
typedef EvaluationSubmitPreparer =
    Future<WriteIntent> Function(List<EvaluationCourseInput> courses);

/// 教学评教启动回调。
typedef EvaluationSubmitStarter =
    Future<void> Function(List<EvaluationCourseInput> courses);

/// 阳光打卡准备回调。
typedef YgdkSubmitPreparer =
    Future<WriteIntent> Function(YgdkSubmitInput input);

/// 阳光打卡启动回调。
typedef YgdkSubmitStarter = Future<void> Function(YgdkSubmitInput input);

/// 阳光打卡照片选择回调。
typedef YgdkPhotoPicker = Future<YgdkPhotoInput?> Function();

/// 场馆预约准备回调。
typedef CgyyReservationPreparer =
    Future<WriteIntent> Function(CgyySubmitInput input);

/// 场馆预约启动回调。
typedef CgyyReservationStarter = Future<void> Function(CgyySubmitInput input);
