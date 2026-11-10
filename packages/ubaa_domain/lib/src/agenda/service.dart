import 'dart:async';
import 'models.dart';
import 'school.dart';
import 'export.dart';
import 'sync.dart';

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
/// 写方法的 Future 必须等持久副作用收尾后再完成，不能另留后台写入。
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

/// 服务的账号代次独立于路线和缓存。关闭同步撤销访问，并等待已交付写入收尾。
/// 排队的旧写入与迟到结果不能流入新账号，挂起读取不阻塞关闭。
final class AgendaService {
  AgendaService(this._backend);
  final AgendaBackend _backend;
  AgendaSyncState _syncState = const AgendaSyncState();
  AgendaSyncState get syncState => _syncState;
  final _syncUpdates = StreamController<AgendaSyncState>.broadcast();
  Stream<AgendaSyncState> get syncUpdates => _syncUpdates.stream;
  Future<void> _syncTail = Future<void>.value();
  bool get supportsSync => _backend is AgendaSyncBackend;
  bool _syncEnabled = false;
  bool get syncEnabled => _syncEnabled;
  void _setSync(AgendaSyncState state) {
    _syncState = AgendaSyncState(
      report: state.report,
      running: state.running,
      error: state.error,
      localPendingCount:
          state.localPendingCount ?? _syncState.localPendingCount,
    );
    if (!_disposed && !_syncUpdates.isClosed) _syncUpdates.add(_syncState);
  }

  Future<AgendaSyncReport> sync(AgendaSyncAction action, AgendaTime now) =>
      Future.sync(() => prepareSync(action, now)());

  /// 在进入确认和排队之前固定账号代次与后端作用域。
  AgendaSyncJob prepareSync(
    AgendaSyncAction action,
    AgendaTime now, {
    void Function(Object)? onRejected,
  }) {
    final backend = _backend;
    if (backend is! AgendaSyncBackend) {
      throw const AgendaException(AgendaFailure.unavailable);
    }
    final generation = _generation;
    AgendaSyncJob work;
    try {
      work = (backend as AgendaSyncBackend).prepareSync(action, now);
    } on Object catch (error) {
      if (action == AgendaSyncAction.createConfirmed &&
          error is AgendaException &&
          error.failure == AgendaFailure.superseded) {
        _setSync(AgendaSyncState(report: _syncState.report, error: error));
      }
      if (generation == _generation && !_disposed) onRejected?.call(error);
      rethrow;
    }
    var started = false;
    return () {
      if (started) {
        return Future.error(const AgendaException(AgendaFailure.superseded));
      }
      started = true;
      final result = _syncTail.then((_) {
        if (generation != _generation || _disposed)
          throw const AgendaException(AgendaFailure.superseded);
        return _run(() async {
          _setSync(AgendaSyncState(report: _syncState.report, running: true));
          try {
            Future<void> refreshPermission() async {
              if (action != AgendaSyncAction.createConfirmed ||
                  generation != _generation ||
                  _disposed)
                return;
              final enabled = await (backend as AgendaSyncBackend)
                  .syncEnabled();
              if (generation == _generation && !_disposed)
                _syncEnabled = enabled;
            }

            final AgendaSyncReport report;
            try {
              report = await work();
            } on Object {
              // 许可核对失败不能掩盖原云端操作的错误。
              try {
                await refreshPermission();
              } on Object {
                /* 保留原错误。 */
              }
              rethrow;
            }
            await refreshPermission();
            if (generation != _generation || _disposed)
              throw const AgendaException(AgendaFailure.superseded);
            _setSync(
              AgendaSyncState(
                report: report,
                localPendingCount: report.pendingCount,
              ),
            );
            return report;
          } on Object catch (error) {
            if (generation == _generation && !_disposed) {
              _setSync(
                AgendaSyncState(report: _syncState.report, error: error),
              );
              onRejected?.call(error);
            }
            rethrow;
          }
        });
      });
      _syncTail = result.then<void>((_) {}, onError: (Object _) {});
      return result;
    };
  }

  void _syncAfterWrite(AgendaTime now) {
    if (!supportsSync) return;
    if (!_syncEnabled) {
      unawaited(
        _refreshLocalPendingCount().then<void>((_) {}, onError: (Object _) {}),
      );
      return;
    }
    unawaited(
      sync(
        AgendaSyncAction.push,
        now,
      ).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  Future<void> _refreshLocalPendingCount() async {
    final generation = _generation;
    final count = await _backend.unsyncedCount();
    if (generation != _generation || _disposed) return;
    _setSync(
      AgendaSyncState(
        report: _syncState.report,
        running: _syncState.running,
        error: _syncState.error,
        localPendingCount: count,
      ),
    );
  }

  int _generation = 0;
  bool _disposed = false;
  String? _account;
  String? get accountId => _account;
  int get accountGeneration => _generation;
  Future<void> _tail = Future<void>.value();
  Future<void> _ready = Future<void>.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> openAccount(String accountId) {
    if (_disposed) {
      return Future.error(const AgendaException(AgendaFailure.inactive));
    }
    final generation = ++_generation;
    _syncTail = Future<void>.value();
    _syncEnabled = false;
    _setSync(const AgendaSyncState(localPendingCount: 0));
    _account = accountId;
    final opened = _serial(() async {
      await _backend.deactivate();
      if (generation != _generation || _disposed) {
        throw const AgendaException(AgendaFailure.superseded);
      }
      await _backend.openAccount(accountId);
      final backend = _backend;
      if (backend is AgendaSyncBackend) {
        final enabled = await (backend as AgendaSyncBackend).syncEnabled();
        if (generation != _generation || _disposed)
          throw const AgendaException(AgendaFailure.superseded);
        _syncEnabled = enabled;
        await _refreshLocalPendingCount();
      }
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
    _syncEnabled = false;
    _syncTail = Future<void>.value();
    _setSync(const AgendaSyncState(localPendingCount: 0));
    return _serial(_backend.deactivate);
  }

  Future<void>? _disposal;
  Future<void> dispose() {
    _disposed = true;
    return _disposal ??= close().then((_) => _syncUpdates.close());
  }

  Future<T> _run<T>(
    Future<T> Function() action, {
    bool write = false,
    AgendaTime? syncNow,
  }) {
    if (_disposed || _account == null) {
      return Future.error(const AgendaException(AgendaFailure.inactive));
    }
    final generation = _generation;
    // 捕获本次打开，后续 open 不得让旧写入等待排在自身后面的打开。
    final ready = _ready;
    void check() {
      if (generation != _generation || _disposed) {
        throw const AgendaException(AgendaFailure.superseded);
      }
    }

    Future<T> invoke() async {
      try {
        await ready;
        check();
        final value = await action();
        check();
        if (syncNow != null) _syncAfterWrite(syncNow);
        return value;
      } on Object {
        check();
        rethrow;
      }
    }

    // 已交付后端的写入先收尾，排队的旧代次写入在交付前拒绝。
    // 读取独立运行，挂起的查询不能阻止关闭。
    return write ? _serial(invoke) : invoke();
  }

  Future<AgendaExportResult> exportIcs(
    AgendaQuery query, {
    bool includeCompleted = false,
  }) => _run(() {
    final backend = _backend;
    if (backend is! AgendaExportBackend)
      throw const AgendaException(AgendaFailure.unavailable);
    return (backend as AgendaExportBackend).exportIcs(query, includeCompleted);
  });
  Future<AgendaQueryResult> query(AgendaQuery query) =>
      _run(() => _backend.query(query));
  Future<AgendaItem> create(AgendaDraft draft, AgendaTime now) =>
      _run(() => _backend.create(draft, now), write: true, syncNow: now);
  Future<AgendaItem?> get(String itemId) => _run(() => _backend.get(itemId));
  Future<String?> editDraft(
    String id,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaDraft draft,
    AgendaTime now,
  ) => _run(
    () {
      final backend = _backend;
      if (backend is! AgendaDraftBackend)
        throw const AgendaException(AgendaFailure.unavailable);
      return (backend as AgendaDraftBackend).editDraft(
        id,
        scope,
        at,
        draft,
        now,
      );
    },
    write: true,
    syncNow: now,
  );
  Future<String?> edit(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaContent content,
    String? rrule,
    AgendaTime now,
  ) => _run(
    () => _backend.edit(itemId, scope, at, content, rrule, now),
    write: true,
    syncNow: now,
  );
  Future<void> delete(
    String itemId,
    AgendaEditScope scope,
    AgendaTime? at,
    AgendaTime now,
  ) => _run(
    () => _backend.delete(itemId, scope, at, now),
    write: true,
    syncNow: now,
  );
  Future<void> complete(
    String itemId,
    AgendaTime? at,
    bool completed,
    AgendaTime now,
  ) => _run(
    () => _backend.complete(itemId, at, completed, now),
    write: true,
    syncNow: now,
  );
  Future<void> setOverlay(AgendaOverlayDraft value, AgendaTime now) =>
      _run(() => _backend.setOverlay(value, now), write: true, syncNow: now);
  Future<AgendaOverlay?> overlay(SchoolAgendaKey key) =>
      _run(() => _backend.overlay(key));
  Future<void> clearOverlay(SchoolAgendaKey key, AgendaTime now) =>
      _run(() => _backend.clearOverlay(key, now), write: true, syncNow: now);
  Future<int> unsyncedCount() => _run(_backend.unsyncedCount);
  Future<int> clearLocalData() {
    final generation = _generation;
    return _run(() async {
      final count = await _backend.clearLocalData();
      if (generation == _generation && !_disposed) {
        _setSync(
          AgendaSyncState(
            report: _syncState.report,
            running: _syncState.running,
            error: _syncState.error,
            localPendingCount: 0,
          ),
        );
      }
      return count;
    }, write: true);
  }

  Future<TeachingWeekRule> teachingWeekRule(TeachingWeekInput input) =>
      _run(() => _backend.teachingWeekRule(input));
}
