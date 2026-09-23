import 'dart:async';

/// 只调度尚未发送的工作；既定写回读不会被普通读取暂停条件阻塞。
enum ReadPriority { writeReadback, urgent, interactive, home, background }

/// 合并的同一读取共享需求；只能提高尚未发送批次的优先级。
final class ReadDemand {
  ReadDemand(this._priority);
  ReadPriority _priority;
  ReadPriority get priority => _priority;
  bool promote(ReadPriority value) {
    if (value.index >= _priority.index) return false;
    _priority = value;
    return true;
  }
}

final class ReadCancelled implements Exception {
  const ReadCancelled();
}

final class _ReadJob {
  _ReadJob(
    this.initialPriority,
    this.current,
    this.execute,
    this.cancel,
    this.continuation,
    this.demand,
  );
  final ReadPriority initialPriority;
  final ReadDemand? demand;
  ReadPriority get priority => demand?.priority ?? initialPriority;
  final bool continuation;
  final bool Function() current;
  final Future<void> Function() execute;
  final void Function() cancel;
}

/// 一次只发出一批。执行回调必须在 Core 的安全返回边界结束。
final class ReadScheduler {
  ReadScheduler({required this.canRun});
  final bool Function(ReadPriority) canRun;
  final _pending = <_ReadJob>[];
  bool _running = false;
  bool _scheduled = false;
  bool _closed = false;

  Future<T> run<T>(
    ReadPriority priority,
    bool Function() current,
    Future<T> Function() operation, {
    void Function(T)? discard,
    bool continuation = false,
    ReadDemand? demand,
  }) {
    final completion = Completer<T>();
    if (_closed) return Future.error(const ReadCancelled());
    _pending.add(
      _ReadJob(
        priority,
        current,
        () async {
          try {
            if (_closed || !current()) throw const ReadCancelled();
            final value = await operation();
            if (_closed || !current()) {
              discard?.call(value);
              throw const ReadCancelled();
            }
            completion.complete(value);
          } on Object catch (error, stack) {
            completion.completeError(
              _closed || !current() ? const ReadCancelled() : error,
              stack,
            );
          }
        },
        () => completion.completeError(const ReadCancelled()),
        continuation,
        demand,
      ),
    );
    pump();
    return completion.future;
  }

  void pump() {
    for (final job in _pending.toList()) {
      if (_closed || !job.current()) {
        _pending.remove(job);
        job.cancel();
      }
    }
    if (_closed || _running || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_closed || _running) return;
      _ReadJob? selected;
      for (final job in _pending) {
        if (canRun(job.priority) &&
            (selected == null ||
                job.priority.index < selected.priority.index ||
                (job.priority == selected.priority &&
                    job.continuation &&
                    !selected.continuation)))
          selected = job;
      }
      if (selected == null) return;
      _pending.remove(selected);
      _running = true;
      unawaited(
        selected.execute().whenComplete(() {
          _running = false;
          pump();
        }),
      );
    });
  }

  void close() {
    _closed = true;
    pump();
  }
}
