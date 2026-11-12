import 'package:ubaa_domain/ubaa_domain.dart';
import '../../../contracts/recovery.dart';

/// 绑定创建时的账号与路线代次，页面不能复用切号前的读取或写入准备。
final class GuardedBhpanService implements BhpanService {
  GuardedBhpanService(
    this.delegate,
    this.current, {
    this.onRejected,
    this.readService,
    this.recordFailure,
  });
  final ServiceRead? readService;
  final UiError Function(Object, StackTrace)? recordFailure;
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
  ) => _run(() => delegate.download(handles, name, path, overwrite, transfer));
  @override
  Future<BhpanDownloadPreparation> downloadPreparation(
    List<String> handles,
    String name,
  ) => _run(() => delegate.downloadPreparation(handles, name));
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
        message: '账号或网络已切换，请重新打开北航云盘',
      );
  }

  Future<T> _run<T>(Future<T> Function() call, {bool record = false}) async {
    _check();
    try {
      final value = await call();
      _check();
      return value;
    } on Object catch (error, stack) {
      if (current()) {
        onRejected?.call(error);
        if (record && recordFailure != null) throw recordFailure!(error, stack);
      }
      rethrow;
    }
  }

  @override
  Future<BhpanCapabilities> capabilities() => _run(delegate.capabilities);
  Future<T> _read<T>(Future<T> Function() call) async {
    _check();
    return readService?.call(RecoveryTarget.bhpan, () => _run(call)) ??
        _run(call, record: true);
  }

  @override
  Future<void> login() => _read(delegate.login);
  @override
  Future<BhpanPage> read(BhpanRead query) => query.target == null
      ? _read(() => delegate.read(query))
      : _run(() => delegate.read(query), record: true);
  @override
  Future<BhpanSize> size(String item) =>
      _run(() => delegate.size(item), record: true);
  @override
  Future<String> suggestName(String parent, String name) =>
      _run(() => delegate.suggestName(parent, name), record: true);
  @override
  Future<List<BhpanShare>> shares({String? item}) =>
      _run(() => delegate.shares(item: item), record: true);
  @override
  Future<String> shareLink(String share) =>
      _run(() => delegate.shareLink(share), record: true);
  @override
  Future<WriteIntent> prepare(BhpanMutation request) =>
      _run(() => delegate.prepare(request));
}
