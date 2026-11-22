part of 'bridge_backend.dart';

mixin BridgeBackendWrite {
  BridgeContext get _context;

  Future<GradeScoreBaseline?> updateGradeScoreBaseline({
    required String accountId,
    required ConnectionMode route,
    required GradeScoreBaseline latest,
    GradeScoreBaseline? legacy,
  }) => bridgeUpdateGradeScoreBaseline(
    _context,
    accountId,
    route,
    latest,
    legacy,
  );

  Future<List<WriteReadbackHint>> readWriteReadbackHints({
    required String accountId,
  }) => bridgeReadWriteReadbackHints(_context, accountId);
  Future<void> dismissWriteReadbackHint(
    String id, {
    required String accountId,
  }) => bridgeDismissWriteReadbackHint(_context, accountId, id);

  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async =>
      bridgePrepareBykcSelectCourse(_context, courseId: courseId);

  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) =>
      bridgePrepareBykcDeselectCourse(_context, courseId: courseId);

  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) => bridgePrepareBykcSignCourse(
    _context,
    courseId: courseId,
    lat: lat,
    lng: lng,
    signType: signType,
  );

  Future<WriteIntent> prepareSigninPerform({required String courseId}) =>
      bridgePrepareSigninPerform(_context, courseId: courseId);

  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) => bridgePrepareLibbookReserve(
    _context,
    areaId: areaId,
    seatId: seatId,
    day: day,
    segment: segment,
    startTime: startTime,
    endTime: endTime,
  );

  Future<WriteIntent> prepareLibbookCancelBooking({
    required String id,
    required int page,
    required int limit,
  }) => bridgePrepareLibbookCancelBooking(
    _context,
    id: id,
    page: page,
    limit: limit,
  );

  /// 准备阳光打卡。照片字节只在本次调用构造 typed DTO，不写入配置或日志。
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) =>
      bridgePrepareYgdkSubmit(_context, input);

  /// 准备研讨室预约；selection 只包含经过 UI 选择的 ID，不接受 raw JSON。
  Future<WriteIntent> prepareCgyySubmitReservation(CgyySubmitInput input) =>
      bridgePrepareCgyySubmitReservation(_context, input);

  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) =>
      bridgePrepareCgyyCancelOrder(_context, id: id);

  /// 评教只回传 Core 签发的稳定目标，并在 commit 后按原路线读取核对。
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationSubmitTarget> targets,
  ) => bridgePrepareEvaluationSubmitCourses(_context, targets);

  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) => bridgeCommitWrite(_context, intentId, cacheAccountId: accountId);

  Future<WriteCommitResult> commitWrite(String intentId) =>
      bridgeCommitWrite(_context, intentId);

  Future<void> discardWriteIntent(String intentId) =>
      bridgeDiscardWriteIntent(_context, intentId);
}
