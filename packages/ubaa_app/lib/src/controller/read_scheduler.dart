import 'dart:async';

/// 只调度尚未发送的工作；既定写回读不会被普通读取暂停条件阻塞。
enum ReadPriority { writeReadback, urgent, interactive, home, background }

enum ReadSchedulerTraceKind { queued, started, completed, cancelled }

final class ReadSchedulerTrace {
  const ReadSchedulerTrace({
    required this.kind,
    required this.priority,
    required this.atUs,
    required this.waitUs,
    required this.runUs,
  });
  final ReadSchedulerTraceKind kind;
  final ReadPriority priority;
  final int atUs;
  final int waitUs;
  final int runUs;
}

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
    this.queuedAtUs,
  );
  final ReadPriority initialPriority;
  final ReadDemand? demand;
  ReadPriority get priority => demand?.priority ?? initialPriority;
  final bool continuation;
  final bool Function() current;
  final Future<void> Function() execute;
  final void Function() cancel;
  final int queuedAtUs;
}

/// 一次只发出一批。执行回调必须在 Core 的安全返回边界结束。
final class ReadScheduler {
  ReadScheduler({required this.canRun, this.onTrace});
  final bool Function(ReadPriority) canRun;
  final void Function(ReadSchedulerTrace trace)? onTrace;
  final _pending = <_ReadJob>[];
  bool _running = false;
  bool _scheduled = false;
  bool _closed = false;

  void _trace(ReadSchedulerTrace trace) {
    try {
      onTrace?.call(trace);
    } on Object {
      // 诊断观察器不可影响读取调度或业务结果。
    }
  }

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
    final queuedAtUs = DateTime.now().microsecondsSinceEpoch;
    _trace(
      ReadSchedulerTrace(
        kind: ReadSchedulerTraceKind.queued,
        priority: priority,
        atUs: queuedAtUs,
        waitUs: 0,
        runUs: 0,
      ),
    );
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
        queuedAtUs,
      ),
    );
    pump();
    return completion.future;
  }

  void pump() {
    for (final job in _pending.toList()) {
      if (_closed || !job.current()) {
        _pending.remove(job);
        final cancelledAtUs = DateTime.now().microsecondsSinceEpoch;
        _trace(
          ReadSchedulerTrace(
            kind: ReadSchedulerTraceKind.cancelled,
            priority: job.priority,
            atUs: cancelledAtUs,
            waitUs: (cancelledAtUs - job.queuedAtUs).clamp(0, 1 << 62),
            runUs: 0,
          ),
        );
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
      final startedAtUs = DateTime.now().microsecondsSinceEpoch;
      _trace(
        ReadSchedulerTrace(
          kind: ReadSchedulerTraceKind.started,
          priority: selected.priority,
          atUs: startedAtUs,
          waitUs: (startedAtUs - selected.queuedAtUs).clamp(0, 1 << 62),
          runUs: 0,
        ),
      );
      unawaited(
        selected.execute().whenComplete(() {
          final completedAtUs = DateTime.now().microsecondsSinceEpoch;
          _trace(
            ReadSchedulerTrace(
              kind: ReadSchedulerTraceKind.completed,
              priority: selected!.priority,
              atUs: completedAtUs,
              waitUs: (startedAtUs - selected.queuedAtUs).clamp(0, 1 << 62),
              runUs: (completedAtUs - startedAtUs).clamp(0, 1 << 62),
            ),
          );
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
