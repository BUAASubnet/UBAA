import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../assignments/backend.dart';
part 'data.dart';

/// 显式合成图书馆宿主；复用离线认证并在内存中消费合成意图。
class LibraryBackend extends CourseworkBackend
    implements LibbookWriteBackend, CancellationWriteBackend {
  LibraryBackend({super.state}) {
    signedIn = true;
  }
  final libraryReads = <FeatureQuery>[];
  final preparedSeats = <LibbookReserveAction>[];
  final preparedBookings = <(String, int, int)>[];
  Completer<void>? pending;
  bool failNext = false;
  bool emptyNext = false;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature != FeatureId.libbook) {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    libraryReads.add(query);
    final gate = pending;
    if (gate != null) await gate.future;
    if (identical(pending, gate)) pending = null;
    if (failNext || (state == 'first-error' && libraryReads.length == 1)) {
      failNext = false;
      throw const BackendException(UbaaErrorCode.networkError);
    }
    if (emptyNext || state == 'empty') {
      emptyNext = false;
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    return libraryData(query, state);
  }

  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) async {
    preparedSeats.add(
      LibbookReserveAction(
        areaId: areaId,
        seatId: seatId,
        day: day,
        segment: segment,
        startTime: startTime,
        endTime: endTime,
        eligibility: ActionEligibility.allowed,
      ),
    );
    return _intent(WriteOperation.libbookReserve, '合成座位 $seatId');
  }

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({
    required String id,
    required int page,
    required int limit,
  }) async {
    preparedBookings.add((id, page, limit));
    return _intent(WriteOperation.libbookCancelBooking, '合成预约 $id');
  }

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) async =>
      throw StateError('图书馆测试不准备研讨室写入');
  final _operations = <String, WriteOperation>{};
  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    final operation = _operations.remove(intentId);
    if (operation == null) throw StateError('合成意图不存在或已消费');
    commitCalls++;
    return WriteCommitResult(
      operation: operation,
      success: true,
      message: '合成操作已提交',
      outcomeUnknown: false,
      resolvedRoute: ConnectionMode.direct,
    );
  }

  WriteIntent _intent(WriteOperation operation, String target) {
    final id = 'library-${preparedSeats.length}-${preparedBookings.length}';
    _operations[id] = operation;
    return WriteIntent(
      intentId: id,
      operation: operation,
      targetSummary: target,
      resolvedRoute: ConnectionMode.direct,
      warnings: const ['显式合成目标，仅在内存中提交'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'synthetic-digest',
    );
  }
}
