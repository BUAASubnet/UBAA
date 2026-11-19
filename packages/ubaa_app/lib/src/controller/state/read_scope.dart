import 'dart:async';

import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 捕获同一个后端与会话代次；只提供有效性，不授予状态写权限。
final class SessionScope {
  SessionScope(this.backend, this.lifecycle, this._current);
  final UbaaBackend backend;
  final int lifecycle;
  final bool Function() _current;
  bool get isCurrent => _current();
}

/// 领域读取额外受业务缓存代次约束；会话与缓存失效不能互相替代。
final class ReadScope {
  ReadScope(this.session, this.cacheEpoch, this._current);
  final SessionScope session;
  final int cacheEpoch;
  final bool Function() _current;
  UbaaBackend get backend => session.backend;
  bool get isCurrent => session.isCurrent && _current();

  bool hasSameOwner(ReadScope other) =>
      identical(backend, other.backend) &&
      session.lifecycle == other.session.lifecycle &&
      cacheEpoch == other.cacheEpoch;
}

/// 同一读取的并发调用共享在途结果。完成后释放句柄，下次重新读取。
final class PendingFeatureRead {
  Future<FeatureResult>? _current;
  Future<FeatureResult>? get current => _current;

  Future<FeatureResult> joinOrStart(Future<FeatureResult> Function() read) {
    if (current case final pending?) return pending;
    final completion = Completer<FeatureResult>();
    final future = _current = completion.future;
    unawaited(() async {
      try {
        completion.complete(await read());
      } on Object catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      } finally {
        if (identical(current, future)) clear();
      }
    }());
    return future;
  }

  void clear() => _current = null;
}
