import 'package:ubaa_domain/ubaa_domain.dart';

/// 博雅签到/签退准备回调；保留读取层给出的完整 typed action。
typedef BykcSignPreparer = Future<WriteIntent> Function(BykcSignAction action);

/// 博雅签到/签退启动回调；不得把是否需要调用方坐标降级为展示字段推测。
typedef BykcSignStarter = Future<void> Function(BykcSignAction action);

/// 课堂签到准备回调；保留 Core 核对的安排目标和 typed 资格。
typedef SigninPreparer =
    Future<WriteIntent> Function(SigninPerformAction action);

/// 课堂签到启动回调；不得从展示字段重建目标或资格。
typedef SigninStarter = Future<void> Function(SigninPerformAction action);

/// 释放尚未提交的一次性意图；成功表示 Bridge 已移除对应 pending 状态。
typedef WriteIntentDiscarder = Future<void> Function(String intentId);

/// 图书馆预约准备回调；保留 Core 给出的完整 typed action。
typedef LibbookReservePreparer =
    Future<WriteIntent> Function(LibbookReserveAction action);

/// 图书馆预约启动回调；不得从展示字段重建目标或资格。
typedef LibbookReserveStarter =
    Future<void> Function(LibbookReserveAction action);

/// 图书馆取消准备回调；保留 Core 给出的稳定目标、资格与同页上下文。
typedef LibbookCancelPreparer =
    Future<WriteIntent> Function(LibbookCancelAction action);

/// 图书馆取消启动回调；不得从展示字段重建目标、资格或分页。
typedef LibbookCancelStarter =
    Future<void> Function(LibbookCancelAction action);

/// 场馆取消准备回调；保留 Core 给出的 canonical 订单观察、资格与目标。
typedef CgyyCancelPreparer =
    Future<WriteIntent> Function(CgyyCancelAction action);

/// 场馆取消启动回调；不得从展示字段重建编号、状态或时间。
typedef CgyyCancelStarter = Future<void> Function(CgyyCancelAction action);

/// 场馆预约提交后，用收据匹配只读订单列表的核对回调。
typedef CgyyReceiptVerifier =
    Future<bool> Function(CgyyReservationReceipt receipt);

/// 场馆取消后的列表+详情只读核对回调。
typedef CgyyCancellationVerifier =
    Future<bool> Function({
      required int orderId,
      required ConnectionMode expectedRoute,
    });

/// 写入后只读核对回调；可选查询来自准备阶段保存的安全本地上下文。
typedef WriteSuccessHandler =
    Future<void> Function(
      WriteOperation operation,
      FeatureQuery? readbackQuery,
    );

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
