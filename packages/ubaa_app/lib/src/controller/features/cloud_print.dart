import 'dart:typed_data';

import 'package:ubaa_domain/ubaa_domain.dart';

import '../../write/coordinator.dart';

final class ScopedCloudPrintService implements CloudPrintService {
  const ScopedCloudPrintService(this.delegate, this.current, this.writer);
  final CloudPrintService delegate;
  final bool Function() current;
  final WriteCoordinator writer;

  @override
  bool get isCurrent => current();

  void _check() {
    if (!current()) {
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '登录状态已变化',
        message: '请重新打开图书馆云打印',
      );
    }
  }

  Future<T> _read<T>(Future<T> Function() call) async {
    _check();
    final result = await call();
    _check();
    return result;
  }

  Future<T> _write<T>(Future<T> Function() call) =>
      writer.runConfirmedBatch(() async {
        _check();
        final result = await call();
        if (!current()) {
          throw const UiError(
            code: UbaaErrorCode.outcomeUnknown,
            title: '请核对操作结果',
            message: '账号或连接已改变，请在原账号的文档列表核对',
          );
        }
        return result;
      });

  @override
  Future<List<PrintDocument>> documents({required bool scans}) =>
      _read(() => delegate.documents(scans: scans));
  @override
  Future<Uint8List> preview(String id, int page) =>
      _read(() => delegate.preview(id, page));
  @override
  Future<Uint8List> scan(String id) => _read(() => delegate.scan(id));
  @override
  Future<Uint8List> scanPdf(List<String> ids) =>
      _read(() => delegate.scanPdf(ids));
  @override
  Future<List<UiError?>> upload(
    List<PrintSource> sources,
    PrintOptions options,
  ) => _write(() => delegate.upload(sources, options));
  @override
  Future<List<UiError?>> delete(List<String> ids, {required bool scans}) =>
      _write(() => delegate.delete(ids, scans: scans));
  @override
  Future<List<PrintStation>> stations() => _read(delegate.stations);
  @override
  Future<PrintRecords> records(
    DateTime begin,
    DateTime end,
    PrintRecordKind kind,
    int page,
  ) => _read(() => delegate.records(begin, end, kind, page));
}
