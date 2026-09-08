part of 'ubaa_app_host.dart';

class _UbaaAppHostState extends State<UbaaAppHost> with WidgetsBindingObserver {
  late final AppController _controller;
  late final YgdkReminderStore _reminderStore;
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode value) => setState(() => _themeMode = value);
  bool _wasBackgrounded = false;
  bool _resumeRecoveryPending = false;
  bool _recoveryInFlight = false;
  bool _disposed = false;

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
      telemetry: widget.telemetry,
    );
    _controller.addListener(_retryPendingRecovery);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_retryPendingRecovery);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      if (widget.backend != null) return;
      _resumeRecoveryPending = true;
      _retryPendingRecovery();
    }
  }

  void _retryPendingRecovery() {
    if (_disposed || !_resumeRecoveryPending || _recoveryInFlight) return;
    if (_controller.isRebuildingBackend ||
        _controller.phase == AppPhase.loggingIn ||
        _controller.phase == AppPhase.checkingSession) {
      return;
    }
    _resumeRecoveryPending = false;
    _recoveryInFlight = true;
    unawaited(_recoverBackend());
  }

  Future<void> _recoverBackend() async {
    try {
      await _controller.rebuildBackend();
    } finally {
      _recoveryInFlight = false;
      if (!_disposed) _retryPendingRecovery();
    }
  }

  @override
  Widget build(BuildContext context) => _buildApplication();
}
