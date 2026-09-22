part of 'ubaa_app_host.dart';

class _UbaaAppHostState extends State<UbaaAppHost> with WidgetsBindingObserver {
  late final AppController _controller;
  late final YgdkReminderStore _reminderStore;
  late final GradeScoreStore _gradeScoreStore;
  late final GradeScoreWatch _gradeWatch;
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode value) => setState(() => _themeMode = value);
  bool _wasBackgrounded = false;
  bool _resumeRecoveryPending = false;
  bool _recoveryInFlight = false;
  bool _disposed = false;
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
        (backend != null
            ? MemoryYgdkReminderStore()
            : FileYgdkReminderStore(
                File('${defaultConfigDirectory()}/ui-reminders.json'),
              ));
    final backendFactory = widget.backendFactory ?? createProductionBackend;
    _controller = AppController(
      backend: backend ?? backendFactory(),
      backendFactory: backend == null ? backendFactory : null,
      credentialVault: widget.credentialVault,
      localAccountStore: widget.localAccountStore,
      telemetry: widget.telemetry,
    );
    _gradeScoreStore =
        widget.gradeScoreStore ??
        (backend != null
            ? MemoryGradeScoreStore()
            : FileGradeScoreStore(
                File('${defaultConfigDirectory()}/ui-grade-scores.json'),
              ));
    _gradeWatch = GradeScoreWatch(
      controller: _controller,
      store: _gradeScoreStore,
    );
    _controller.addListener(_retryPendingRecovery);
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
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
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

  @override
  Widget build(BuildContext context) => _buildApplication();
}
