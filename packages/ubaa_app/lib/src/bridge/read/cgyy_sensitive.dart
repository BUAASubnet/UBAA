part of '../bridge_backend.dart';

class _BridgeLockDisplaySession implements CgyyLockDisplaySession {
  _BridgeLockDisplaySession(this.client, this.lease);
  final BridgeClient client;
  final BridgeCgyyLockDisplayLease lease;
  final _cancelled = StreamController<void>.broadcast(sync: true);
  bool _closed = false;
  CgyyLockDisplay? _last;
  @override
  Stream<void> get cancelled => _cancelled.stream;
  @override
  Future<CgyyLockDisplay> read() async {
    if (_closed) throw const BackendException(UbaaErrorCode.invalidInput);
    _last?.release();
    _last = null;
    final value = await client.readCgyyLockDisplay(lease: lease);
    if (_closed) throw const BackendException(UbaaErrorCode.invalidInput);
    return _last = CgyyLockDisplay(
      code: value.code,
      dueDate: value.dueDate,
      reservationReference: value.reservationReference,
      venueName: value.venueName,
      siteName: value.siteName,
      spaceName: value.spaceName,
      orderName: value.orderName,
      reservationDate: value.reservationDate,
      reservationDateDetail: value.reservationDateDetail,
      reservationStartDate: value.reservationStartDate,
      reservationEndDate: value.reservationEndDate,
    );
  }

  @override
  void cancel() {
    if (_closed) return;
    _closed = true;
    lease.cancel();
    _last?.release();
    _last = null;
    _cancelled.add(null);
    unawaited(_cancelled.close());
  }
}
