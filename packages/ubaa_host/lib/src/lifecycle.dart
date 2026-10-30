part of 'ubaa_app_host.dart';

class _UbaaAppHostState extends State<UbaaAppHost> with WidgetsBindingObserver {
  AppController? _readyController;
  AppController get _controller => _readyController!;
  late YgdkReminderStore _reminderStore;
  late GradeScoreStore _gradeScoreStore;
  late BykcCourseFilterStore _bykcFilterStore;
  late CgyyReservationDefaultsStore _cgyyDefaultsStore;
  late RecentFeatureStore _recentFeatureStore;
  late GradeScoreWatch _gradeWatch;
  final _startupDiagnostics = LocalDiagnostics();
  UiError? _startupError;
  int _startupGeneration = 0;
  void _updateStartup(VoidCallback update) {
    if (mounted) setState(update);
  }

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  UiError? _scheduledHomeFeedback;
  late PlacePreferenceStore _placeStore;
  late ThemePreferenceStore _themeStore;
  String? _placeOwner;
  bool _placesReady = false;
  Map<String, String> _placePreferences = {};
  int _themeRevision = 0;
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode value) {
    _themeRevision++;
    setState(() => _themeMode = value);
    unawaited(_themeStore.write(value.name).catchError((Object _) {}));
  }

  Future<void> _restoreTheme() async {
    final revision = _themeRevision;
    final mode = await _themeStore.read();
    if (mounted && revision == _themeRevision) {
      setState(() => _themeMode = ThemeMode.values.byName(mode));
    }
  }

  void _syncPlaces() {
    if (_controller.phase != AppPhase.home) {
      _homeFrameReported = false;
      _placeOwner = null;
      _placesReady = false;
      _placePreferences = {};
      return;
    }
    final owner = _controller.localDataOwnerScope;
    if (_placeOwner == owner.accountKey) return;
    _placeOwner = owner.accountKey;
    _placePreferences = {};
    _placesReady = owner.accountKey.isEmpty;
    if (_placesReady) return;
    unawaited(_restorePlaces(owner));
  }

  Future<void> _restorePlaces(LocalDataOwnerScope owner) async {
    final value = await _placeStore.read(owner.accountKey);
    try {
      owner.checkCurrent();
      if (mounted)
        setState(() {
          _placePreferences = value;
          _placesReady = true;
        });
    } on Object {
      /* 旧账号的异步读取结果丢弃。 */
    }
  }

  Future<void> _savePlace(
    LocalDataOwnerScope owner,
    String key,
    String value,
  ) async {
    try {
      owner.checkCurrent();
      if (!UiPlaceKeys.all.contains(key)) return;
      _placePreferences = {..._placePreferences, key: value};
      unawaited(
        _placeStore
            .write(owner.accountKey, _placePreferences)
            .catchError((Object _) {}),
      );
    } on Object {
      /* 普通偏好写失败不打断操作。 */
    }
  }

  bool _wasBackgrounded = false;
  // 启动和登录期间收到的恢复事件，等首页首帧后再交给同一恢复任务。
  bool _homeFrameReported = false;
  bool _resumeRecoveryPending = false;
  bool _recoveryInFlight = false;
  bool _disposed = false;
  ScheduleWidgetPublisher? _scheduleWidgetPublisher;
  (String?, Object)? _scheduleWidgetStamp;
  Stream<void>? _networkChanges;
  StreamSubscription<void>? _networkSubscription;

  void _listenNetworkChanges() {
    if (_wasBackgrounded) return;
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
    _wasBackgrounded = switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached => true,
      _ => false,
    };
    WidgetsBinding.instance.addObserver(this);
    if (widget.backend case final backend?) {
      _installBackend(backend);
    } else {
      unawaited(_openBackend());
    }
  }

  void _installBackend(UbaaBackend opened) {
    final backend = widget.backend;
    final preferences =
        widget.preferenceValues ??
        (backend != null || widget.backendFactory != null
            ? MemoryPreferenceValues()
            : PluginPreferenceValues());
    _placeStore =
        widget.preferenceValues == null &&
            (backend != null || widget.backendFactory != null)
        ? PlacePreferenceStore.memory(allowedKeys: UiPlaceKeys.all)
        : PlacePreferenceStore(
            scope: backend != null || widget.backendFactory != null
                ? 'synthetic'
                : defaultConfigDirectory(),
            allowedKeys: UiPlaceKeys.all,
            values: preferences,
          );
    _themeStore = ThemePreferenceStore(values: preferences);
    unawaited(_restoreTheme());
    _reminderStore =
        widget.reminderStore ??
        (backend != null || widget.backendFactory != null
            ? MemoryYgdkReminderStore()
            : PreferencesYgdkReminderStore(scope: defaultConfigDirectory()));
    final backendFactory = widget.backendFactory ?? createProductionBackend;
    _readyController = AppController(
      backend: opened,
      backendFactory: backend == null ? backendFactory : null,
      credentialVault: widget.credentialVault,
      localAccountStore: widget.localAccountStore,
      telemetry: widget.telemetry,
      onReadSchedulerTrace: widget.onReadSchedulerTrace,
    );
    _controller.setAppForeground(!_wasBackgrounded);
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
    _cgyyDefaultsStore =
        widget.cgyyDefaultsStore ??
        (backend != null || widget.backendFactory != null
            ? MemoryCgyyReservationDefaultsStore()
            : PreferencesCgyyReservationDefaultsStore(
                scope: defaultConfigDirectory(),
              ));
    _recentFeatureStore =
        widget.recentFeatureStore ??
        (backend != null || widget.backendFactory != null
            ? MemoryRecentFeatureStore()
            : PreferencesRecentFeatureStore(scope: defaultConfigDirectory()));
    _controller.addListener(_syncPlaces);
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
    if (_readyController == null) {
      super.dispose();
      return;
    }
    _controller.removeListener(_syncPlaces);
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
      _readyController?.setAppForeground(false);
      return;
    }
    // inactive 已有可见窗口；桌面可能一直没有焦点，不能等待 resumed 才解暂停。
    final visible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (visible && _wasBackgrounded) {
      _wasBackgrounded = false;
      if (_readyController == null) return;
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
        !_homeFrameReported ||
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
      UbaaFeedback.showOn(
        messenger,
        error.message,
        kind: UbaaFeedbackKind.error,
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      _readyController == null ? _buildStartup() : _buildApplication();
}
