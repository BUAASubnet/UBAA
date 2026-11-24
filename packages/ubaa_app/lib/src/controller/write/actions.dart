import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/write.dart';
import 'package:ubaa_app/src/write/cgyy_validation.dart';
import 'package:ubaa_app/src/write/ygdk_validation.dart';
import '../state/state.dart' show ControllerState;
import '../write/cgyy_readback.dart' show controllerVerifyCgyyCancellation;
import '../write/evaluation_readback.dart'
    show
        controllerNormalizeEvaluationTarget,
        controllerRefreshEvaluationAfterWrite;
import '../write/ygdk_readback.dart' show controllerRefreshYgdkAfterWrite;

mixin ControllerWriteActions on ControllerState {
  SpocWriteBackend get _spocWriter {
    final backend = internalBackend;
    if (backend is! SpocWriteBackend)
      throw const BackendException(UbaaErrorCode.unsupported);
    return backend as SpocWriteBackend;
  }

  BhpanTransferTask createSpocTransfer() => _spocWriter.createSpocTransfer();
  Future<WriteIntent> prepareSpocSubmitAssignment(
    SpocSubmitAction action,
    String path, {
    BhpanTransferTask? transfer,
  }) => internalUserSchoolAction(
    () => _spocWriter.prepareSpocSubmitAssignment(
      action,
      path,
      transfer: transfer,
    ),
  );
  Future<void> refreshWriteReadbacks() =>
      internalLoadWriteReadbacks(force: true);

  Future<void> dismissWriteReadback(String id) =>
      internalDismissControllerReadback(id);

  /// 准备博雅选课/退选的 typed 一次性意图；准备本身不提交写请求。
  Future<WriteIntent> prepareBykcWrite(
    WriteOperation operation,
    int courseId,
  ) => internalUserSchoolAction(() async {
    final backend = internalBackend;
    if (backend is! BykcWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final writer = backend as BykcWriteBackend;
    if (courseId <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return switch (operation) {
      WriteOperation.bykcSelectCourse => writer.prepareBykcSelectCourse(
        courseId: courseId,
      ),
      WriteOperation.bykcDeselectCourse => writer.prepareBykcDeselectCourse(
        courseId: courseId,
      ),
      _ => throw const BackendException(UbaaErrorCode.invalidInput),
    };
  });

  /// 准备博雅签到/签退；仅接受冻结合同的 signType 1/2 和完整有效坐标对。
  Future<WriteIntent> prepareBykcSignWrite(
    int courseId,
    int signType, {
    double? lat,
    double? lng,
  }) => internalUserSchoolAction(() async {
    final backend = internalBackend;
    if (backend is! BykcWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final hasNoCoordinates = lat == null && lng == null;
    final hasValidCoordinates =
        lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
    if (courseId <= 0 ||
        (signType != 1 && signType != 2) ||
        (!hasNoCoordinates && !hasValidCoordinates)) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final writer = backend as BykcWriteBackend;
    return writer.prepareBykcSignCourse(
      courseId: courseId,
      lat: lat,
      lng: lng,
      signType: signType,
    );
  });

  /// 准备课堂签到的 typed 一次性意图；目标和资格必须来自读取白名单。
  Future<WriteIntent> prepareSigninWrite(SigninPerformAction action) =>
      internalUserSchoolAction(() async {
        final backend = internalBackend;
        if (backend is! SigninWriteBackend) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        final writer = backend as SigninWriteBackend;
        final normalized = action.scheduleId.trim();
        if (normalized.isEmpty ||
            action.eligibility != ActionEligibility.allowed) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        return writer.prepareSigninPerform(courseId: normalized);
      });

  /// 准备研讨室取消的一次性意图；只接受 Core 给出的 typed 目标。
  Future<WriteIntent> prepareCgyyCancelWrite(CgyyCancelAction action) =>
      internalUserSchoolAction(() async {
        final backend = internalBackend;
        if (backend is! CancellationWriteBackend) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        if (!action.hasCanonicalTarget) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        return (backend as CancellationWriteBackend).prepareCgyyCancelOrder(
          id: action.orderId,
        );
      });

  /// 准备图书馆取消意图；目标、资格与分页上下文全部来自 Core typed 读取。
  Future<WriteIntent> prepareLibbookCancelWrite(LibbookCancelAction action) =>
      internalUserSchoolAction(() async {
        final backend = internalBackend;
        if (backend is! CancellationWriteBackend) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        final bookingId = action.bookingId.trim();
        if (action.eligibility != ActionEligibility.allowed ||
            bookingId.isEmpty ||
            action.page <= 0 ||
            action.limit <= 0) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        final writer = backend as CancellationWriteBackend;
        return writer.prepareLibbookCancelBooking(
          id: bookingId,
          page: action.page,
          limit: action.limit,
        );
      });

  /// 准备图书馆预约的 typed 一次性意图；只接受读取白名单中的完整目标。
  Future<WriteIntent> prepareLibbookReserveWrite(LibbookReserveAction action) =>
      internalUserSchoolAction(() async {
        final backend = internalBackend;
        if (backend is! LibbookWriteBackend) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        final values = <String>[
          action.areaId,
          action.seatId,
          action.day,
          action.segment,
          action.startTime,
          action.endTime,
        ].map((value) => value.trim()).toList(growable: false);
        if (action.eligibility != ActionEligibility.allowed ||
            values.any((value) => value.isEmpty)) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        final writer = backend as LibbookWriteBackend;
        return writer.prepareLibbookReserve(
          areaId: values[0],
          seatId: values[1],
          day: values[2],
          segment: values[3],
          startTime: values[4],
          endTime: values[5],
        );
      });

  /// 准备阳光打卡写意图；照片字节只复制到本次内存请求，不落盘或写日志。
  Future<WriteIntent> prepareYgdkWrite(YgdkSubmitInput input) =>
      internalUserSchoolAction(() async {
        final backend = internalBackend;
        if (backend is! YgdkWriteBackend) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        return (backend as YgdkWriteBackend).prepareYgdkSubmit(
          validateYgdkSubmitInput(input),
        );
      });

  /// 准备研讨室预约写意图；只接受 Core 已核对的 typed actions。
  Future<WriteIntent> prepareCgyySubmitWrite(CgyySubmitInput input) =>
      internalUserSchoolAction(() async {
        final backend = internalBackend;
        if (backend is! CgyyWriteBackend) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        return (backend as CgyyWriteBackend).prepareCgyySubmitReservation(
          validateCgyySubmitInput(input),
        );
      });

  /// 准备教学评教写意图；仅接受读取 action 中的 typed 目标。
  Future<WriteIntent> prepareEvaluationWrite(
    List<EvaluationSubmitTarget> targets,
  ) => internalUserSchoolAction(() async {
    final backend = internalBackend;
    if (backend is! EvaluationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final normalized = targets
        .map(controllerNormalizeEvaluationTarget)
        .toList(growable: false);
    final uniqueKeys = normalized.map((target) => target.selectionKey).toSet();
    if (normalized.isEmpty ||
        normalized.any((target) => !target.hasRequiredIdentity) ||
        uniqueKeys.length != normalized.length) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return (backend as EvaluationWriteBackend).prepareEvaluationSubmitCourses(
      normalized,
    );
  });

  /// 提交已确认的一次性意图；不接受任意请求正文，也不自动重试。
  Future<WriteCommitResult> commitWrite(String intentId) =>
      internalUserSchoolAction(
        () => internalCommitWriteWithBackend(internalBackend, intentId),
      );

  /// 释放尚未确认的一次性意图；该操作不提交任何上游写请求。
  Future<void> discardWriteIntent(String intentId) =>
      internalDiscardWriteWithBackend(internalBackend, intentId);

  /// 写入成功后仅刷新关联只读领域，用于结果核对；不会重试写请求。
  Future<void> refreshAfterWrite(
    WriteOperation operation, [
    FeatureQuery? readbackQuery,
  ]) => internalRefreshAfterWrite(operation, readbackQuery);

  /// 在研讨室订单刷新完成后，仅按公开订单编号匹配提交收据。
  ///
  /// 该方法不发起额外请求，调用方必须先等待 [refreshAfterWrite]；读取失败、
  /// 空结果或不匹配均返回 `false`，绝不把写入结果升级为已核对。
  Future<bool> matchesCgyyReceipt(CgyyReservationReceipt receipt) async {
    if (receipt.orderId <= 0) return false;
    final snapshot = internalSnapshots[FeatureId.cgyy];
    if (snapshot == null || snapshot.status != FeatureLoadStatus.success) {
      return false;
    }
    final orderId = receipt.orderId.toString();
    return snapshot.details.any(
      (detail) => detail.fields.any(
        (field) => field.label == '订单编号' && field.value == orderId,
      ),
    );
  }

  /// 在 intent 的实际路线上执行研讨室取消列表+详情双回读。
  Future<bool> verifyCgyyCancellation({
    required int orderId,
    required ConnectionMode expectedRoute,
  }) => controllerVerifyCgyyCancellation(
    this,
    orderId: orderId,
    expectedRoute: expectedRoute,
  );

  /// 在 intent 的实际路线 best-effort 刷新阳光打卡概览与首页记录。
  ///
  /// 冻结来源没有提供记录与本次写入的严格关联规则，因此该方法不
  /// 接收收据也不返回核对结论，更不得将 OutcomeUnknown 升级为成功。
  Future<void> refreshYgdkAfterWrite({required ConnectionMode expectedRoute}) =>
      controllerRefreshYgdkAfterWrite(this, expectedRoute: expectedRoute);

  /// 在 intent 的实际路线 best-effort 刷新评教课程。
  ///
  /// 该回读只更新 Evaluation 快照，不改写结果，也不会重试提交。
  Future<void> refreshEvaluationAfterWrite({
    required ConnectionMode expectedRoute,
  }) =>
      controllerRefreshEvaluationAfterWrite(this, expectedRoute: expectedRoute);
}
