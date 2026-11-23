import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart' show DiagnosticOperation;
import '../../../contracts/recovery.dart';

/// 绑定创建时的账号与路线代次，页面不能复用切号前的读取或写入准备。
final class GuardedBhpanService implements BhpanService {
  GuardedBhpanService(
    this.delegate,
    this.current, {
    this.onRejected,
    this.readService,
    this.recordFailure,
    this.recordOutcome,
  });
  final ServiceRead? readService;
  final ServiceFailureRecorder? recordFailure;
  final ServiceOutcomeRecorder? recordOutcome;
  final BhpanService delegate;
  final bool Function() current;
  final void Function(Object)? onRejected;
  @override
  Future<BhpanDownloadReceipt> download(
    List<String> handles,
    String name,
    String path,
    bool overwrite,
    BhpanTransferTask transfer,
  ) => _run(
    () => delegate.download(handles, name, path, overwrite, transfer),
    operation: DiagnosticOperation.bhpanDownload,
  );
  @override
  Future<BhpanDownloadPreparation> downloadPreparation(
    List<String> handles,
    String name,
  ) => _run(
    () => delegate.downloadPreparation(handles, name),
    operation: DiagnosticOperation.bhpanDownloadPreparation,
  );
  @override
  BhpanTransferTask createTransfer() {
    _check();
    return delegate.createTransfer();
  }

  void _check() {
    if (!current())
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '登录状态已变化',
        message: '账号或网络已切换，请重新打开云盘',
      );
  }

  Future<T> _run<T>(
    Future<T> Function() call, {
    DiagnosticOperation? operation,
  }) async {
    _check();
    final elapsed = Stopwatch()..start();
    try {
      final value = await call();
      _check();
      if (operation != null) {
        recordOutcome?.call(
          operation,
          route: value is BhpanPage ? value.route : null,
        );
      }
      return value;
    } on Object catch (error, stack) {
      if (current()) {
        onRejected?.call(error);
        if (operation != null) {
          final recorded = recordFailure?.call(
            error,
            operation,
            stack,
            latency: elapsed.elapsed,
          );
          if (recorded != null) {
            recordOutcome?.call(operation, error: recorded);
            throw recorded;
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<BhpanCapabilities> capabilities() => _run(delegate.capabilities);
  Future<T> _read<T>(
    DiagnosticOperation operation,
    Future<T> Function() call,
  ) async {
    _check();
    return readService?.call(
          RecoveryTarget.bhpan,
          operation,
          () => _run(call),
        ) ??
        _run(call, operation: operation);
  }

  @override
  Future<void> login() => _read(DiagnosticOperation.bhpanLogin, delegate.login);
  @override
  Future<BhpanPage> read(BhpanRead query) => query.target == null
      ? _read(DiagnosticOperation.bhpanList, () => delegate.read(query))
      : _run(
          () => delegate.read(query),
          operation: DiagnosticOperation.bhpanList,
        );
  @override
  Future<BhpanSize> size(String item) =>
      _run(() => delegate.size(item), operation: DiagnosticOperation.bhpanSize);
  @override
  Future<String> suggestName(String parent, String name) => _run(
    () => delegate.suggestName(parent, name),
    operation: DiagnosticOperation.bhpanSuggestName,
  );
  @override
  Future<List<BhpanShare>> shares({String? item}) => _run(
    () => delegate.shares(item: item),
    operation: DiagnosticOperation.bhpanShares,
  );
  @override
  Future<String> shareLink(String share) => _run(
    () => delegate.shareLink(share),
    operation: DiagnosticOperation.bhpanShareLink,
  );
  @override
  Future<WriteIntent> prepare(BhpanMutation request) =>
      _run(() => delegate.prepare(request));
}
