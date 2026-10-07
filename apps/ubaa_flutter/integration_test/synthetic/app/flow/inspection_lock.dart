part of '../flow_test.dart';

/// 独立合成短期显示，不访问网络，也不把密码放进普通读取结果。
class _InspectionLockSession implements CgyyLockDisplaySession {
  final _events = StreamController<void>.broadcast(sync: true);
  bool _closed = false;

  @override
  Stream<void> get cancelled => _events.stream;

  @override
  Future<CgyyLockDisplay> read() async {
    if (_closed) throw const BackendException(UbaaErrorCode.invalidInput);
    return CgyyLockDisplay(
      code: '001234',
      reservationReference: 'synthetic-reference',
      orderName: '合成预约人',
    );
  }

  @override
  void cancel() {
    if (_closed) return;
    _closed = true;
    _events.add(null);
    unawaited(_events.close());
  }
}
