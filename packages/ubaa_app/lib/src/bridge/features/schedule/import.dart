part of 'reader.dart';

Future<ScheduleImportTask> bridgeBeginScheduleImport(
  BridgeContext backend,
  String term,
) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
  final generation = backend.cache.generation;
  if (cache == null || account == null) {
    throw const BackendException(UbaaErrorCode.unsupported);
  }
  BridgeScheduleImportTask? task;
  try {
    task = await backend.client.beginScheduleImport(cache: cache, term: term);
    bridgeCheckOfflineGeneration(backend, generation);
    return _ScheduleImportTask(backend, task, generation, term);
  } on BridgeError catch (error) {
    task?.cancel();
    bridgeCheckOfflineGeneration(backend, generation);
    throw bridgeMapError(error);
  } on Object {
    task?.cancel();
    rethrow;
  }
}

final class _ScheduleImportTask implements ScheduleImportTask {
  _ScheduleImportTask(this.backend, this.task, this.generation, this.term);
  final BridgeContext backend;
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
    bridgeCheckOfflineGeneration(backend, generation);
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
        route: bridgeToConnectionMode(progress.route.resolvedRoute),
        saveFailure: bridgeCacheMaintenanceFailure(progress.saveError),
      );
    } on BridgeError catch (error) {
      try {
        _checkCurrent();
        throw bridgeMapError(error);
      } finally {
        cancel();
      }
    } on Object {
      cancel();
      rethrow;
    }
  }
}
