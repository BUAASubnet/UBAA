import 'package:ubaa_domain/ubaa_domain.dart';

/// 可释放尚未提交的一次性意图。
///
/// 丢弃只删除 Bridge 内存中的 pending intent，不发送上游写请求。
abstract interface class WriteIntentDiscardBackend {
  Future<void> discardWriteIntent(String intentId);
}

/// 生产写入的统一确认能力。
///
/// 任何可提交或准备 typed 写意图的 backend 都必须同时提供
/// [discardWriteIntent]，保证宿主在展示确认页前已具备完整生命周期能力。
abstract interface class WriteCommitBackend
    implements WriteIntentDiscardBackend {
  Future<WriteCommitResult> commitWrite(String intentId);
}

/// 已接入 typed 写意图的博雅课程能力。
///
/// 该接口只暴露公开课程 ID 和一次性意图；确认提交仍需单独调用
/// [commitWrite]。未实现本能力的测试 backend 仍可安全保持只读。
abstract interface class BykcWriteBackend implements WriteCommitBackend {
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId});

  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId});

  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  });
}

/// 已接入 typed 课堂签到写意图的能力。
///
/// 课程编号直接来自签到读取 DTO 的公开字段；位置/挑战等未证明参数不在
/// 该简化入口中猜测，Core 会按冻结合同决定是否需要额外条件。
abstract interface class SigninWriteBackend implements WriteCommitBackend {
  Future<WriteIntent> prepareSigninPerform({required String courseId});
}

/// 已接入图书馆/场馆可逆取消的 typed 写意图能力。
abstract interface class CancellationWriteBackend
    implements WriteCommitBackend {
  Future<WriteIntent> prepareLibbookCancelBooking({required String id});

  Future<WriteIntent> prepareCgyyCancelOrder({required int id});
}

/// 已接入图书馆座位预约的 typed 写意图能力。
abstract interface class LibbookWriteBackend implements WriteCommitBackend {
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  });
}

/// 已接入 typed 阳光打卡写意图的能力。
abstract interface class YgdkWriteBackend implements WriteCommitBackend {
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input);
}

/// 已接入 typed 场馆预约写意图的能力；验证码材料不由宿主构造或保存。
abstract interface class CgyyWriteBackend implements WriteCommitBackend {
  Future<WriteIntent> prepareCgyySubmitReservation(CgyySubmitInput input);
}

/// 已接入 typed 教学评教写意图的能力；仅传递冻结课程标识字段。
abstract interface class EvaluationWriteBackend implements WriteCommitBackend {
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationCourseInput> courses,
  );
}
