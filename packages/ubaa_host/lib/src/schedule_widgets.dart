part of 'ubaa_app_host.dart';

extension _UbaaAppHostWidgets on _UbaaAppHostState {
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

  void _syncScheduleWidgets() {
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
    if (stamp == _scheduleWidgetStamp) return;
    _scheduleWidgetStamp = stamp;
    unawaited(
      publisher.update(stamp.$1, _controller.readScheduleWidgets).catchError((
        Object error,
      ) {
        if (_disposed ||
            stamp != _scheduleWidgetStamp ||
            error is BackendException &&
                error.code == UbaaErrorCode.operationConflict)
          return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_disposed && stamp == _scheduleWidgetStamp) {
            _messengerKey.currentState?.showSnackBar(
              const SnackBar(content: Text('桌面课表暂时不可用，请重新保存课表后重试。')),
            );
          }
        });
      }),
    );
  }
}
