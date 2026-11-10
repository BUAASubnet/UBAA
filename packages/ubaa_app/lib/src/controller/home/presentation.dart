import 'dart:async';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../state/state.dart';
import '../state/types.dart';
import 'coordinator.dart';

mixin ControllerHomePresentation on ControllerState {
  bool _homeAttached = false;
  bool _homeVisible = true;
  bool get homeVisible => _homeVisible;

  /// GUI 组合根订阅首页时启用编排，命令与独立查询不隐式读取补充来源。
  void attachHomePresentation({bool visible = true}) {
    _homeAttached = true;
    _homeVisible = visible;
    internalSyncHome();
  }

  late final _home = HomeCoordinator(
    loadSupplement: (source, force) =>
        internalLoadHomeSupplement(source, forceRefresh: force),
    loadDay: (date, force) =>
        internalLoadHomeDaySchedule(date, forceRefresh: force),
    project: projectHomeTodos,
    refreshMain: () => internalRefreshHome(firstBatch: true),
    retryMain: (feature) =>
        internalRefreshHome(only: [feature], firstBatch: true),
    readCachedWeek: internalReadCachedHomeWeek,
    readCachedDay: internalReadCachedHomeDay,
    changed: internalNotify,
    reportUserRejection: internalReportSchoolRejection,
    scheduleBackground: (action) =>
        internalAutomaticSchoolAction(() => scheduleMicrotask(action)),
  );
  HomeState get homeState => _home.state;
  Future<void> refreshHomePage() => internalUserSchoolAction(_home.refresh);
  Future<void> retryHomeSource(FeatureId feature) =>
      internalUserSchoolAction(() => _home.retry(feature));
  void setHomeReminder(YgdkReminderSettings? value) => _home.setReminder(value);
  void setHomeVisible(bool value) {
    if (_homeVisible == value) return;
    _homeVisible = value;
    internalSyncHome();
  }

  @override
  @internal
  void internalSyncHome() {
    if (!_homeAttached) return;
    _home.update(
      owner: (
        internalBackend,
        internalLifecycleEpoch,
        internalBusinessCacheEpoch,
        internalLocalAccount?.id,
        internalUser?.username,
        internalRoutePolicyGeneration,
      ),
      contentScope: (
        internalLocalAccount?.id ?? internalUser?.username,
        internalBusinessCacheEpoch,
        internalRoutePolicyGeneration,
      ),
      snapshots: homeSnapshots,
      epoch: internalReadCacheEpoch,
      agenda: internalAgendaEpoch,
      active:
          !internalIsSigningOut &&
          (internalPhase == AppPhase.home ||
              (internalPhase == AppPhase.checkingSession &&
                  internalLocalAccount != null)),
      online:
          _homeVisible &&
          internalPhase == AppPhase.home &&
          (!internalUsesLocalRecovery ||
              internalSessionRecoveryStatus == SessionRecoveryStatus.ready),
      blocked: homeTodoProjectionBlocked,
      foreground: internalAppForeground,
      readDays: _homeVisible,
    );
  }

  @override
  @internal
  Future<void> internalFlushHomeProjection() =>
      _homeAttached ? _home.flushProjection() : Future.value();

  @override
  @internal
  void internalDisposeHome() => _home.dispose();
}
