import 'package:ubaa_app/src/contracts/backend.dart';
import 'read_scope.dart';

/// 会话身份与生命周期只有此处可以修改；不承担 UI 通知或学校认证。
final class SessionLifecycleOwner {
  SessionLifecycleOwner(this._backend);
  UbaaBackend _backend;
  int _epoch = 0;
  int _transition = 0;
  bool _disposed = false;
  bool _signingOut = false;
  bool _rebuilding = false;
  UbaaBackend get backend => _backend;
  int get epoch => _epoch;
  bool get disposed => _disposed;
  bool get signingOut => _signingOut;
  bool get rebuilding => _rebuilding;

  int invalidate() => ++_epoch;
  void replaceBackend(UbaaBackend value) {
    _backend = value;
    _transition++;
  }

  void beginSignOut() {
    _signingOut = true;
    _transition++;
  }

  void endSignOut() {
    _signingOut = false;
  }

  void beginRebuild() {
    _rebuilding = true;
    _transition++;
  }

  void endRebuild() {
    _rebuilding = false;
  }

  void dispose() {
    _disposed = true;
    _transition++;
  }

  SessionScope capture() {
    final backend = _backend, epoch = _epoch, transition = _transition;
    return SessionScope(
      backend,
      epoch,
      () =>
          !_disposed &&
          !_signingOut &&
          !_rebuilding &&
          identical(backend, _backend) &&
          epoch == _epoch &&
          transition == _transition,
    );
  }
}

/// 读取缓存与离线账号库拥有不同代次；清理不赋予任何会话权限。
final class CacheLifecycleOwner {
  int _readEpoch = 0;
  int _offlineEpoch = 0;
  bool _clearing = false;
  int get readEpoch => _readEpoch;
  int get offlineEpoch => _offlineEpoch;
  bool get clearing => _clearing;
  int invalidateReads() => ++_readEpoch;
  int invalidateOffline() => ++_offlineEpoch;
  void beginClearing() {
    _clearing = true;
  }

  void endClearing() {
    _clearing = false;
  }

  ReadScope captureRead(SessionScope session) {
    final epoch = _readEpoch;
    return ReadScope(session, epoch, () => !_clearing && epoch == _readEpoch);
  }

  OfflineAccountScope captureOffline({
    required SessionScope session,
    required String? accountId,
    required Future<void> opened,
    required bool Function() accountCurrent,
  }) {
    final read = captureRead(session), epoch = _offlineEpoch;
    return OfflineAccountScope(
      read,
      accountId,
      opened,
      () => epoch == _offlineEpoch && accountCurrent(),
    );
  }
}

/// 本地账号库操作的能力快照；公开查询代替分散的生命周期布尔组合。
final class OfflineAccountScope {
  OfflineAccountScope(this.read, this.accountId, this.opened, this._current);
  final ReadScope read;
  final String? accountId;
  final Future<void> opened;
  final bool Function() _current;
  UbaaBackend get backend => read.backend;
  bool get isCurrent => read.isCurrent && _current();
}
