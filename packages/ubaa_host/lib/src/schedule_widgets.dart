part of 'ubaa_app_host.dart';

extension _UbaaAppHostWidgets on _UbaaAppHostState {
  String? get _widgetHomeOwner {
    final controller = _readyController;
    final owner = controller?.scheduleWidgetOwner;
    return !_disposed &&
            controller?.phase == AppPhase.home &&
            owner?.isNotEmpty == true
        ? owner
        : null;
  }

  void _syncWidgetLaunchOwner() {
    if (_widgetColdOwner != _widgetHomeOwner) _widgetColdOwner = null;
  }

  Future<void> _takeWidgetLink({bool cold = false}) async {
    final owner = _widgetHomeOwner;
    final channel = _widgetLaunch;
    if (channel == null || owner == null || (cold && owner == _widgetColdOwner))
      return;
    if (cold) _widgetColdOwner = owner;
    final String? raw;
    try {
      raw = await channel.take();
    } on Object {
      return;
    }
    if (owner == _widgetHomeOwner && raw != null) await _launchWidgetLink(raw);
  }

  Future<void> _launchWidgetLink(String raw) async {
    if (_disposed) return;
    final shell = _shellKey.currentState;
    if (shell == null) {
      _pendingWidgetLink = raw;
      return;
    }
    final owner = _widgetHomeOwner;
    final target = parseWidgetLaunch(raw, owner: owner);
    if (target == null) return;
    await shell.openWidget(
      target,
      _controller.widgetWeekOn,
      () => owner == _widgetHomeOwner,
    );
  }

  Future<void> _revokeScheduleWidgets() async {
    await _scheduleWidgetPublisher?.update(
      null,
      (_) => throw const BackendException(UbaaErrorCode.operationConflict),
    );
  }

  Future<CacheClearOutcome> _clearCacheAndWidgets(String accountId) async {
    final result = _controller.clearBusinessCache(accountId: accountId);
    final values = await Future.wait<Object?>([
      result,
      _revokeScheduleWidgets(),
    ]);
    return values.first! as CacheClearOutcome;
  }

  void _syncScheduleWidgets() => _publishScheduleWidgets();

  void _publishScheduleWidgets({bool immediate = false}) {
    final publisher = _scheduleWidgetPublisher;
    if (_disposed ||
        publisher == null ||
        _controller.phase == AppPhase.splash ||
        _controller.phase == AppPhase.checkingSession)
      return;
    final stamp = (
      _controller.scheduleWidgetOwner,
      _controller.scheduleWidgetRevision,
    );
    if (!immediate && stamp == _scheduleWidgetStamp) return;
    _scheduleWidgetStamp = stamp;
    unawaited(
      publisher
          .update(
            stamp.$1,
            _controller.readScheduleWidgets,
            immediate: immediate,
          )
          .catchError((Object error) {
            if (_disposed ||
                stamp != _scheduleWidgetStamp ||
                error is BackendException &&
                    error.code == UbaaErrorCode.operationConflict)
              return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_disposed && stamp == _scheduleWidgetStamp) {
                final messenger = _messengerKey.currentState;
                if (messenger != null)
                  UbaaFeedback.showOn(
                    messenger,
                    '桌面小组件更新失败，请刷新课表后重试',
                    kind: UbaaFeedbackKind.warning,
                  );
              }
            });
          }),
    );
  }
}
