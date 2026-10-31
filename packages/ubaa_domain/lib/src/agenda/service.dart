import 'dart:async';
import 'models.dart';
import 'school.dart';

/// 日程文件不属于可丢弃的学校缓存，宿主应单独展示错误并保留文件。
final class AgendaException implements Exception {
  const AgendaException(this.failure);
  final AgendaFailure failure;
  @override
  String toString() => '本机日程操作失败（${failure.name}）';
}

abstract interface class AgendaProvider {
  AgendaService get agenda;
}

/// 生产实现只调用独立 typed Bridge 句柄，不获取网络客户端锁。
abstract interface class AgendaBackend {
  Future<void> openAccount(String accountId);
  Future<void> deactivate();
  Future<AgendaQueryResult> query(AgendaQuery query);
  Future<AgendaItem> create(AgendaDraft draft, AgendaTime now);
  Future<AgendaItem?> get(String itemId);
  Future<String?> edit(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaContent content,
    String? rrule,
    AgendaTime now,
  );
  Future<void> delete(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaTime now,
  );
  Future<void> complete(
    String itemId,
    AgendaTime? at,
    bool completed,
    AgendaTime now,
  );
  Future<void> setOverlay(AgendaOverlayDraft value, AgendaTime now);
  Future<AgendaOverlay?> overlay(SchoolAgendaKey key);
  Future<void> clearOverlay(SchoolAgendaKey key, AgendaTime now);
  Future<int> unsyncedCount();
  Future<int> clearLocalData();
  Future<TeachingWeekRule> teachingWeekRule(TeachingWeekInput input);
}

/// 服务的账号代次独立于路线和缓存。关闭同步撤销访问，迟到结果不能流入新账号。
final class AgendaService {
  AgendaService(this._backend);
  final AgendaBackend _backend;
  int _generation = 0;
  bool _disposed = false;
  String? _account;
  String? get accountId => _account;
  Future<void> _tail = Future<void>.value();
  Future<void> _ready = Future<void>.value();
  Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> openAccount(String accountId) {
    if (_disposed) {
      return Future.error(const AgendaException(AgendaFailure.inactive));
    }
    final generation = ++_generation;
    _account = accountId;
    final opened = _serial(() async {
      await _backend.deactivate();
      if (generation != _generation || _disposed) {
        throw const AgendaException(AgendaFailure.superseded);
      }
      await _backend.openAccount(accountId);
      if (generation != _generation || _disposed) {
        await _backend.deactivate();
        throw const AgendaException(AgendaFailure.superseded);
      }
    });
    _ready = opened;
    // 调用方和后续业务操作均可收到打开错误；避免尚未发起业务操作时产生未处理错误。
    unawaited(opened.then<void>((_) {}, onError: (Object _) {}));
    return opened;
  }

  Future<void> close() {
    _generation++;
    _account = null;
    return _serial(_backend.deactivate);
  }

  Future<void>? _disposal;
  Future<void> dispose() {
    _disposed = true;
    return _disposal ??= close();
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_disposed || _account == null) {
      throw const AgendaException(AgendaFailure.inactive);
    }
    final generation = _generation;
    void check() {
      if (generation != _generation || _disposed) {
        throw const AgendaException(AgendaFailure.superseded);
      }
    }

    try {
      await _ready;
      check();
      final value = await action();
      check();
      return value;
    } on Object {
      check();
      rethrow;
    }
  }

  Future<AgendaQueryResult> query(AgendaQuery query) =>
      _run(() => _backend.query(query));
  Future<AgendaItem> create(AgendaDraft draft, AgendaTime now) =>
      _run(() => _backend.create(draft, now));
  Future<AgendaItem?> get(String itemId) => _run(() => _backend.get(itemId));
  Future<String?> edit(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaContent content,
    String? rrule,
    AgendaTime now,
  ) => _run(() => _backend.edit(itemId, scope, at, content, rrule, now));
  Future<void> delete(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaTime now,
  ) => _run(() => _backend.delete(itemId, scope, at, now));
  Future<void> complete(
    String itemId,
    AgendaTime? at,
    bool completed,
    AgendaTime now,
  ) => _run(() => _backend.complete(itemId, at, completed, now));
  Future<void> setOverlay(AgendaOverlayDraft value, AgendaTime now) =>
      _run(() => _backend.setOverlay(value, now));
  Future<AgendaOverlay?> overlay(SchoolAgendaKey key) =>
      _run(() => _backend.overlay(key));
  Future<void> clearOverlay(SchoolAgendaKey key, AgendaTime now) =>
      _run(() => _backend.clearOverlay(key, now));
  Future<int> unsyncedCount() => _run(_backend.unsyncedCount);
  Future<int> clearLocalData() => _run(_backend.clearLocalData);
  Future<TeachingWeekRule> teachingWeekRule(TeachingWeekInput input) =>
      _run(() => _backend.teachingWeekRule(input));
}
