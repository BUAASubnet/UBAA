import 'package:ubaa_domain/ubaa_domain.dart';

/// 绑定创建时的账号与路线代次，页面不能复用切号前的读取或写入准备。
final class GuardedBhpanService implements BhpanService {
  GuardedBhpanService(this.delegate, this.current);
  final BhpanService delegate;
  final bool Function() current;
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
        title: '会话已变化',
        message: '账号或路线已变化，请重新打开北航云盘',
      );
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    _check();
    final value = await call();
    _check();
    return value;
  }

  @override
  Future<BhpanCapabilities> capabilities() => _run(delegate.capabilities);
  @override
  Future<void> login() => _run(delegate.login);
  @override
  Future<BhpanPage> read(BhpanRead query) => _run(() => delegate.read(query));
  @override
  Future<BhpanSize> size(String item) => _run(() => delegate.size(item));
  @override
  Future<String> suggestName(String parent, String name) =>
      _run(() => delegate.suggestName(parent, name));
  @override
  Future<List<BhpanShare>> shares({String? item}) =>
      _run(() => delegate.shares(item: item));
  @override
  Future<String> shareLink(String share) =>
      _run(() => delegate.shareLink(share));
  @override
  Future<WriteIntent> prepare(BhpanMutation request) =>
      _run(() => delegate.prepare(request));
}
