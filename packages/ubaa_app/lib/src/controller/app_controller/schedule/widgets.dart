part of '../../app_controller.dart';

/// 当前账号与缓存代次约束下的离线组件投影。
extension ScheduleWidgetCache on AppController {
  String? get scheduleWidgetOwner =>
      _phase == AppPhase.home && !_isSigningOut && !_clearingBusinessCache
      ? _localAccount?.id
      : null;
  Object get scheduleWidgetRevision => (
    _businessCacheEpoch,
    _backend,
    Object.hashAll(
      _scheduleImports.entries
          .where((e) => e.value.status == ScheduleImportStatus.saved)
          .map((e) => (e.key, e.value.progress)),
    ),
  );
  Future<ScheduleWidgetSnapshot> readScheduleWidgets(
    bool Function() publisherCurrent,
  ) async {
    final owner = scheduleWidgetOwner,
        epoch = _lifecycleEpoch,
        backend = _backend;
    final cacheEpoch = _businessCacheEpoch;
    if (owner == null || backend is! OfflineQueryBackend) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    await _offlineOpenFuture;
    return readScheduleWidgetSnapshot(
      backend: backend as OfflineQueryBackend,
      owner: owner,
      policy: RoutePolicy.auto,
      isCurrent: () =>
          publisherCurrent() &&
          !_disposed &&
          epoch == _lifecycleEpoch &&
          identical(backend, _backend) &&
          owner == scheduleWidgetOwner &&
          cacheEpoch == _businessCacheEpoch,
    );
  }
}
