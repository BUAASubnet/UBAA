part of 'ubaa_app_host.dart';

class _UbaaAppHostState extends State<UbaaAppHost> with WidgetsBindingObserver {
  late final AppController _controller;
  late final YgdkReminderStore _reminderStore;
  late final GradeScoreStore _gradeScoreStore;
  late final BykcCourseFilterStore _bykcFilterStore;
  late final GradeScoreWatch _gradeWatch;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  UiError? _scheduledHomeFeedback;
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode value) => setState(() => _themeMode = value);
  bool _wasBackgrounded = false;
  bool _resumeRecoveryPending = false;
  bool _recoveryInFlight = false;
  bool _disposed = false;
  ScheduleWidgetPublisher? _scheduleWidgetPublisher;
  (String?, Object)? _scheduleWidgetStamp;
  Stream<void>? _networkChanges;
  StreamSubscription<void>? _networkSubscription;

  void _listenNetworkChanges() {
    _networkSubscription ??= _networkChanges?.listen(
      (_) => _controller.onNetworkChanged(),
      onError: (Object _) {},
    );
  }

  void _stopNetworkChanges() {
    final subscription = _networkSubscription;
    _networkSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final backend = widget.backend;
    _reminderStore =
        widget.reminderStore ??
        (backend != null || widget.backendFactory != null
            ? MemoryYgdkReminderStore()
            : PreferencesYgdkReminderStore(scope: defaultConfigDirectory()));
    final backendFactory = widget.backendFactory ?? createProductionBackend;
    _controller = AppController(
      backend: backend ?? backendFactory(),
      backendFactory: backend == null ? backendFactory : null,
      credentialVault: widget.credentialVault,
      localAccountStore: widget.localAccountStore,
      telemetry: widget.telemetry,
      onReadSchedulerTrace: widget.onReadSchedulerTrace,
    );
    _gradeScoreStore =
        widget.gradeScoreStore ??
        (backend != null
            ? MemoryGradeScoreStore()
            : ControllerGradeScoreStore(_controller));
    _gradeWatch = GradeScoreWatch(
      controller: _controller,
      store: _gradeScoreStore,
      onCheckComplete: widget.onGradeCheckComplete,
    );
    _bykcFilterStore =
        widget.bykcFilterStore ??
        (backend != null || widget.backendFactory != null
            ? MemoryBykcCourseFilterStore()
            : PreferencesBykcCourseFilterStore(
                scope: defaultConfigDirectory(),
              ));
    _controller.addListener(_retryPendingRecovery);
    _controller.addListener(_showHomeFeedback);
    final widgetGateway =
        widget.scheduleWidgetGateway ??
        (Platform.isAndroid &&
                widget.backend == null &&
                widget.backendFactory == null
            ? const AndroidScheduleWidgetGateway()
            : null);
    if (widgetGateway != null) {
      _scheduleWidgetPublisher = ScheduleWidgetPublisher(widgetGateway);
      _controller.addListener(_syncScheduleWidgets);
    }
    _networkChanges =
        widget.networkChanges ??
        (widget.backend == null && widget.backendFactory == null
            ? LocalNetworkMonitor().changes
            : null);
    _listenNetworkChanges();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _disposed = true;
    _stopNetworkChanges();
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_retryPendingRecovery);
    _controller.removeListener(_showHomeFeedback);
    _controller.removeListener(_syncScheduleWidgets);
    _scheduleWidgetPublisher?.dispose();
    _gradeWatch.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
      _stopNetworkChanges();
      _controller.setAppForeground(false);
      return;
    }
    // inactive 已有可见窗口；桌面可能一直没有焦点，不能等待 resumed 才解暂停。
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (visible && _wasBackgrounded) {
      _wasBackgrounded = false;
      _listenNetworkChanges();
      _controller.setAppForeground(true);
      if (_recoveryInFlight) return;
      _resumeRecoveryPending = true;
      _retryPendingRecovery();
    }
  }

  void _retryPendingRecovery() {
    if (_disposed ||
        _wasBackgrounded ||
        !_resumeRecoveryPending ||
        _recoveryInFlight)
      return;
    if (_controller.isRebuildingBackend ||
        _controller.isLoggingIn ||
        _controller.phase == AppPhase.checkingSession) {
      return;
    }
    if (_controller.phase == AppPhase.home && _controller.error != null) return;
    _resumeRecoveryPending = false;
    _recoveryInFlight = true;
    unawaited(_recoverBackend());
  }

  Future<void> _recoverBackend() async {
    try {
      await _controller.resumeSession();
    } finally {
      _recoveryInFlight = false;
      if (!_disposed) _retryPendingRecovery();
    }
  }

  void _showHomeFeedback() {
    if (_disposed || _controller.phase != AppPhase.home) return;
    final error = _controller.error;
    if (error == null || identical(error, _scheduledHomeFeedback)) return;
    _scheduledHomeFeedback = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_scheduledHomeFeedback, error)) {
        _scheduledHomeFeedback = null;
      }
      if (_disposed ||
          _controller.phase != AppPhase.home ||
          !identical(_controller.error, error))
        return;
      final messenger = _messengerKey.currentState;
      if (messenger == null) return;
      // 首页绘制完成后消费一次，避免各只读来源的刷新反复显示同一提示。
      _controller.clearError();
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    });
  }

  @override
  Widget build(BuildContext context) => _buildApplication();
}
