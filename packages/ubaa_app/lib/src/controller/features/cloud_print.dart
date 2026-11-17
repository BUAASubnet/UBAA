import 'dart:typed_data';

import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart' show DiagnosticOperation;

import '../../contracts/recovery.dart';
import '../../write/coordinator.dart';

final class ScopedCloudPrintService implements CloudPrintService {
  const ScopedCloudPrintService(
    this.delegate,
    this.current,
    this.writer,
    this.recordFailure,
    this.recordOutcome,
  );
  final CloudPrintService delegate;
  final bool Function() current;
  final WriteCoordinator writer;
  final ServiceFailureRecorder recordFailure;
  final ServiceOutcomeRecorder recordOutcome;

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

  Future<T> _read<T>(
    DiagnosticOperation operation,
    Future<T> Function() call,
  ) async {
    _check();
    final elapsed = Stopwatch()..start();
    try {
      final result = await call();
      _check();
      recordOutcome(operation);
      return result;
    } on Object catch (error, stack) {
      if (!current()) rethrow;
      final recorded = recordFailure(
        error,
        operation,
        stack,
        latency: elapsed.elapsed,
      );
      recordOutcome(operation, error: recorded);
      throw recorded;
    }
  }

  Future<List<UiError?>> _write(
    DiagnosticOperation operation,
    Future<List<UiError?>> Function() call,
  ) => writer.runConfirmedBatch(() async {
    _check();
    final elapsed = Stopwatch()..start();
    try {
      final result = await call();
      if (!current()) {
        throw const UiError(
          code: UbaaErrorCode.outcomeUnknown,
          title: '请核对操作结果',
          message: '账号或连接已改变，请在原账号的文档列表核对',
        );
      }
      final recorded = [
        for (final (index, error) in result.indexed)
          error == null
              ? null
              : recordFailure(
                  error,
                  operation,
                  StackTrace.current,
                  fileIndex: index + 1,
                  latency: elapsed.elapsed,
                ),
      ];
      recordOutcome(
        operation,
        write: true,
        error: recorded.whereType<UiError>().firstOrNull,
      );
      return recorded;
    } on Object catch (error, stack) {
      if (!current()) rethrow;
      final recorded = recordFailure(
        error,
        operation,
        stack,
        latency: elapsed.elapsed,
      );
      recordOutcome(operation, write: true, error: recorded);
      throw recorded;
    }
  });

  @override
  Future<List<PrintDocument>> documents({required bool scans}) => _read(
    DiagnosticOperation.cloudPrintDocuments,
    () => delegate.documents(scans: scans),
  );
  @override
  Future<Uint8List> preview(String id, int page) => _read(
    DiagnosticOperation.cloudPrintPreview,
    () => delegate.preview(id, page),
  );
  @override
  Future<Uint8List> scan(String id) =>
      _read(DiagnosticOperation.cloudPrintScan, () => delegate.scan(id));
  @override
  Future<Uint8List> scanPdf(List<String> ids) =>
      _read(DiagnosticOperation.cloudPrintScanPdf, () => delegate.scanPdf(ids));
  @override
  Future<List<UiError?>> upload(
    List<PrintSource> sources,
    PrintOptions options,
  ) => _write(
    DiagnosticOperation.cloudPrintUpload,
    () => delegate.upload(sources, options),
  );
  @override
  Future<List<UiError?>> delete(List<String> ids, {required bool scans}) =>
      _write(
        DiagnosticOperation.cloudPrintDelete,
        () => delegate.delete(ids, scans: scans),
      );
  @override
  Future<List<PrintStation>> stations() =>
      _read(DiagnosticOperation.cloudPrintStations, delegate.stations);
  @override
  Future<PrintRecords> records(
    DateTime begin,
    DateTime end,
    PrintRecordKind kind,
    int page,
  ) => _read(
    DiagnosticOperation.cloudPrintRecords,
    () => delegate.records(begin, end, kind, page),
  );
}
