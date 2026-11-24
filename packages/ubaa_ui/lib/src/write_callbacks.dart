import 'package:ubaa_domain/ubaa_domain.dart';

export 'features/coursework/signin_qr_sheet.dart' show SigninQrImageSaver;

/// 按排课标识和时间偏移读取二维码内容。
typedef SigninCourseQrFetcher =
    Future<String> Function(String courseId, Duration offset);

/// 按排课标识读取最新签到状态，已签到返回 true；读取失败抛错。
typedef SigninStatusChecker = Future<bool> Function(String courseId);

/// 把领域准备函数交给应用层唯一写入协调器。
typedef WritePreparationRunner =
    Future<WriteIntent?> Function(
      Future<WriteIntent> Function() prepare, {
      required WriteOperation expectedOperation,
    });

/// 取消或确认只向宿主发出命令，UI 不直接消费 Bridge intent。
typedef WriteCancellationRunner = Future<void> Function();
typedef WriteConfirmationRunner = Future<WriteOutcome?> Function();

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

/// 研讨室取消准备回调；保留 Core 给出的 canonical 订单观察、资格与目标。
typedef CgyyCancelPreparer =
    Future<WriteIntent> Function(CgyyCancelAction action);

/// 研讨室取消启动回调；不得从展示字段重建编号、状态或时间。
typedef CgyyCancelStarter = Future<void> Function(CgyyCancelAction action);

/// 研讨室预约提交后，用收据匹配只读订单列表的核对回调。
typedef CgyyReceiptVerifier =
    Future<bool> Function(CgyyReservationReceipt receipt);

/// 研讨室取消后的列表+详情只读核对回调。
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

/// 教学评教准备回调；只传递读取 action 中的稳定 typed 目标。
typedef EvaluationSubmitPreparer =
    Future<WriteIntent> Function(List<EvaluationSubmitTarget> targets);

/// 教学评教启动回调；不得从展示字段重建任务、问卷、课程或教师代码。
typedef EvaluationSubmitStarter =
    Future<void> Function(List<EvaluationSubmitTarget> targets);

/// 教学评教提交后的原路线课程与进度回读。
///
/// 回读只用于更新展示与核对结果，不得升级未知结果或触发写入重试。
typedef EvaluationSubmissionRefresher =
    Future<void> Function({required ConnectionMode expectedRoute});

/// 阳光打卡准备回调。
typedef YgdkSubmitPreparer =
    Future<WriteIntent> Function(YgdkSubmitInput input);

/// 阳光打卡启动回调。
typedef YgdkSubmitStarter = Future<void> Function(YgdkSubmitInput input);

/// SPOC 作业提交选中的本地文件：只交付位置与名称，内容由 Core 有界读取。
final class SpocSubmitFile {
  const SpocSubmitFile({required this.path, required this.name});
  final String path, name;
}

/// SPOC 文件作业提交：目标来自读取层的 typed action，不在界面重建。
final class SpocSubmitInput {
  const SpocSubmitInput({required this.action, required this.file});
  final SpocSubmitAction action;
  final SpocSubmitFile file;
}

typedef SpocSubmitStarter = Future<void> Function(SpocSubmitInput input);

/// 准备 SPOC 提交意图；资源释放和大小校验发生在宿主读取文件之前。
typedef SpocSubmitPreparer =
    Future<WriteIntent> Function(SpocSubmitInput input);

/// 选择要提交的本机文件；取消返回 null。
typedef SpocSubmitFilePicker = Future<SpocSubmitFile?> Function();

/// 阳光打卡照片选择回调。
typedef YgdkPhotoPicker = Future<YgdkPhotoInput?> Function();

/// 阳光打卡提交后的原路线概览+记录回读。
///
/// 回读只刷新展示，不接收收据也不返回“已核对”结论。
typedef YgdkSubmissionRefresher =
    Future<void> Function({required ConnectionMode expectedRoute});

/// 研讨室预约准备回调。
typedef CgyyReservationPreparer =
    Future<WriteIntent> Function(CgyySubmitInput input);

/// 研讨室预约启动回调。
typedef CgyyReservationStarter = Future<void> Function(CgyySubmitInput input);

/// 图书续借启动回调；确认、一次性意图和提交由应用层统一写入协调器完成。
typedef LibraryLoanRenewStarter = Future<WriteOutcome?> Function(String loanId);

/// 图书续借准备回调；只传递当前账号读取结果中的记录标识。
typedef LibraryLoanRenewPreparer = Future<WriteIntent> Function(String loanId);
