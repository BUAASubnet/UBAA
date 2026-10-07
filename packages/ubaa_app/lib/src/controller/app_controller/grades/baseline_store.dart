part of '../../app_controller.dart';

/// 跟随控制器账号与缓存代次的加密基线，不另开学校客户端。
final class ControllerGradeScoreStore implements GradeScoreStore {
  ControllerGradeScoreStore(this.controller);
  final AppController controller;

  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline latest,
  ) async {
    final c = controller, backend = controller._backend;
    final local = c._localAccount;
    final lifecycle = c._lifecycleEpoch, epoch = c._readCacheEpoch;
    final cacheEpoch = c._offlineAccountEpoch;
    bool current() =>
        !c._disposed &&
        !c._isSigningOut &&
        !c._rebuildingBackend &&
        !c._clearingBusinessCache &&
        c._phase == AppPhase.home &&
        identical(c._backend, backend) &&
        c._localAccount?.id == local?.id &&
        c._lifecycleEpoch == lifecycle &&
        c._readCacheEpoch == epoch &&
        c._offlineAccountEpoch == cacheEpoch &&
        [c._user?.schoolId, c._user?.username].contains(account);
    void check() {
      if (!current())
        throw const BackendException(UbaaErrorCode.operationConflict);
    }

    check();
    await c._offlineOpenFuture;
    check();
    if (local == null || backend is! GradeScoreBaselineBackend) {
      throw const BackendException(
        UbaaErrorCode.internalError,
        cacheFailure: CacheMaintenanceFailure.unavailable,
      );
    }
    final previous = await (backend as GradeScoreBaselineBackend)
        .updateGradeScoreBaseline(
          accountId: local.id,
          route: route,
          latest: latest,
        );
    check();
    return previous;
  }

  // 加密成绩由控制器的缓存清理/账号退出统一管理，没有第二套文件仓库。
  @override
  Future<void> clearAccount(String account) async {}
}
