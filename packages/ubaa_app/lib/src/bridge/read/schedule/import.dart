part of '../../bridge_backend.dart';

Future<ScheduleImportTask> _beginScheduleImport(
  BridgeBackend backend,
  String term,
) async {
  await _awaitOfflineScope(backend);
  final cache = backend._offlineCache, account = backend._offlineAccount;
  final generation = backend._offlineGeneration;
  if (cache == null || account == null) {
    throw const BackendException(UbaaErrorCode.unsupported);
  }
  BridgeScheduleImportTask? task;
  try {
    task = await backend.client.beginScheduleImport(cache: cache, term: term);
    _checkOfflineGeneration(backend, generation);
    return _ScheduleImportTask(backend, task, generation, term);
  } on BridgeError catch (error) {
    task?.cancel();
    _checkOfflineGeneration(backend, generation);
    throw _mapError(error);
  } on Object {
    task?.cancel();
    rethrow;
  }
}

final class _ScheduleImportTask implements ScheduleImportTask {
  _ScheduleImportTask(this.backend, this.task, this.generation, this.term);
  final BridgeBackend backend;
  final BridgeScheduleImportTask task;
  final int generation;
  final String term;
  bool _cancelled = false;
  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    task.cancel();
  }

  void _checkCurrent() {
    if (_cancelled)
      throw const BackendException(UbaaErrorCode.operationConflict);
    _checkOfflineGeneration(backend, generation);
  }

  @override
  Future<ScheduleImportProgress> next() async {
    try {
      _checkCurrent();
      final progress = await backend.client.nextScheduleImport(task: task);
      _checkCurrent();
      if (progress.termCode != term)
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      return ScheduleImportProgress(
        term: term,
        completedWeeks: progress.completedWeeks,
        totalWeeks: progress.totalWeeks,
        finished: progress.finished,
        route: _toConnectionMode(progress.route.resolvedRoute),
        saveFailure: _cacheMaintenanceFailure(progress.saveError),
      );
    } on BridgeError catch (error) {
      try {
        _checkCurrent();
        throw _mapError(error);
      } finally {
        cancel();
      }
    } on Object {
      cancel();
      rethrow;
    }
  }
}
