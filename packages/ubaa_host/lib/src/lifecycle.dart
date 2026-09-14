part of 'ubaa_app_host.dart';

class _UbaaAppHostState extends State<UbaaAppHost> with WidgetsBindingObserver {
  late final AppController _controller;
  late final YgdkReminderStore _reminderStore;
  late final GradeScoreStore _gradeScoreStore;
  late final GradeScoreWatch _gradeWatch;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  UiError? _scheduledHomeFeedback;
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
    _controller.addListener(_showHomeFeedback);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_retryPendingRecovery);
    _controller.removeListener(_showHomeFeedback);
    _gradeWatch.dispose();
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
    // 先让已确认登录后的本地失败提示在首页显示一次；消费提示发出的
    // 通知会继续恢复，避免重建初始化先清空尚未显示的反馈。
    if (_controller.phase == AppPhase.home && _controller.error != null) return;
    if (_controller.isRebuildingBackend ||
        _controller.isLoggingOut ||
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
