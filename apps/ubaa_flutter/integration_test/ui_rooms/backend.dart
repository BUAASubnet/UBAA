import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_coursework/backend.dart';
part 'data.dart';

/// 研讨室原生验收只使用显式合成数据；基础commit方法一律拒绝。
class RoomBackend extends CourseworkBackend
    implements CgyyWriteBackend, CancellationWriteBackend {
  RoomBackend({super.state}) {
    signedIn = true;
  }
  final roomReads = <FeatureQuery>[];
  final preparedRooms = <CgyySubmitInput>[];
  final preparedOrders = <int>[];
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
    if (feature != FeatureId.cgyy) {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    roomReads.add(query);
    final gate = pending;
    if (gate != null) await gate.future;
    if (identical(gate, pending)) pending = null;
    if (failNext || (state == 'first-error' && roomReads.length == 1)) {
      failNext = false;
      throw const BackendException(UbaaErrorCode.networkError);
    }
    if (emptyNext || state == 'empty') {
      emptyNext = false;
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    return roomData(query, state);
  }

  @override
  Future<WriteIntent> prepareCgyySubmitReservation(
    CgyySubmitInput input,
  ) async {
    preparedRooms.add(input);
    return _intent(WriteOperation.cgyySubmitReservation, '合成研讨室');
  }

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) async {
    preparedOrders.add(id);
    return _intent(WriteOperation.cgyyCancelOrder, '合成研讨室订单 $id');
  }

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({
    required String id,
    required int page,
    required int limit,
  }) async => throw StateError('研讨室测试不准备图书馆写入');
  WriteIntent _intent(WriteOperation operation, String target) => WriteIntent(
    intentId: 'rooms-${preparedRooms.length}-${preparedOrders.length}',
    operation: operation,
    targetSummary: target,
    resolvedRoute: ConnectionMode.direct,
    warnings: const ['显式合成数据，仅准备与取消'],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'synthetic-digest',
  );
}
