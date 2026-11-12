/// 需要协调读取与写入的应用操作；每次开始都有独立占用。
enum ControllerActivityKind {
  initialization,
  authentication,
  routeChange,
  signOut,
  backendRebuild,
  cacheClear,
  recovery,
  serviceRecovery,
}

/// 集中管理操作重叠，不承担会话代次或写意图的生命周期。
final class ControllerActivityOwner {
  final _active = <ControllerActivity>{};

  bool get hasActive => _active.isNotEmpty;
  bool get onlyRecovery =>
      _active.length == 1 &&
      _active.single.kind == ControllerActivityKind.recovery;

  /// 本地投影可以与会话恢复并行，其余操作等待收尾。
  bool get blocksHomeProjection => _active.any(
    (activity) => activity.kind != ControllerActivityKind.recovery,
  );

  /// 目标恢复沿读取队列运行，其在途批次继续由读取调度器管理。
  bool blocksScheduledRead({required bool recoveryRunsInReadLane}) =>
      hasActive &&
      !(recoveryRunsInReadLane &&
          _active.any(
            (activity) => activity.kind == ControllerActivityKind.recovery,
          ));

  ControllerActivity begin(ControllerActivityKind kind) {
    final activity = ControllerActivity._(this, kind);
    _active.add(activity);
    return activity;
  }
}

/// 完成只释放本次占用，嵌套或重叠的其他操作继续生效。
final class ControllerActivity {
  ControllerActivity._(this._owner, this.kind);
  final ControllerActivityOwner _owner;
  final ControllerActivityKind kind;
  void finish() => _owner._active.remove(this);
}
