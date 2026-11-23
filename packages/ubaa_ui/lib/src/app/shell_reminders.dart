part of 'shell.dart';

extension UbaaShellReminders on _UbaaMainShellState {
  YgdkReminderSettings? get _effectiveReminder => _reminderSettings == null
      ? null
      : effectiveYgdkReminder(_reminderSettings!, _ygdkSchedule.hasPe);

  void _checkYgdkSchedule() => unawaited(
    _ygdkSchedule.update(
      owner:
          widget.cacheAccountId ??
          widget.user?.accountScope ??
          widget.user?.username,
      epoch: (widget.agendaEpoch, widget.businessCacheEpoch),
      service: widget.agenda.service,
      policy: widget.routePolicy,
      active: widget.activeRoutes,
      schoolRoute: widget.agendaSchoolRoute,
      term: widget.agenda.term,
      now: (widget.homeClock ?? clock).now(),
      changed: () {
        if (mounted) _changeNavigation(_publishReminder);
      },
    ),
  );

  void _publishReminder() {
    final value = _effectiveReminder;
    _publishedReminderEnabled = value?.enabled;
    widget.onHomeReminderChanged?.call(value);
  }

  Future<void> _loadReminderSettings() async {
    final generation = _accountGeneration;
    final revision = _reminderRevision;
    final load = widget.onLoadYgdkReminder;
    if (load == null) {
      _reminderSettings = const YgdkReminderSettings();
      _publishReminder();
      return;
    }
    try {
      final value = await load();
      if (mounted &&
          generation == _accountGeneration &&
          revision == _reminderRevision) {
        _changeNavigation(() => _reminderSettings = value);
        _publishReminder();
      }
    } on Object {
      if (mounted &&
          generation == _accountGeneration &&
          revision == _reminderRevision)
        _changeNavigation(() => _reminderError = '提醒设置读取失败');
    }
  }

  Future<void> _saveReminderSettings(YgdkReminderSettings value) async {
    final save = widget.onSaveYgdkReminder;
    if (save == null) return;
    final before = _reminderSettings, generation = _accountGeneration;
    final revision = ++_reminderRevision;
    _changeNavigation(() {
      _reminderSettings = value;
      _publishReminder();
      _reminderError = null;
    });
    try {
      await save(value);
    } on Object {
      if (mounted &&
          generation == _accountGeneration &&
          revision == _reminderRevision) {
        _changeNavigation(() {
          _reminderSettings = before;
          _publishReminder();
          _reminderError = '提醒设置保存失败，请重试';
        });
      }
    }
  }

  void _setReminderEnabled(bool enabled) {
    final current = _reminderSettings;
    if (current != null)
      unawaited(
        _saveReminderSettings(
          current.copyWith(enabled: enabled, manualEnabled: enabled),
        ),
      );
  }

  void _observeHomeProgress(WeekPresentation week, YgdkOverview overview) {
    if (_effectiveReminder?.enabled != true) return;
    final next = observedReminderProgress(_reminderSettings, week, overview);
    if (next != null) unawaited(_saveReminderSettings(next));
  }
}
