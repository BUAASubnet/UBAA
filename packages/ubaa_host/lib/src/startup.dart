part of 'ubaa_app_host.dart';

extension _BackendStartup on _UbaaAppHostState {
  Future<UbaaBackend> _createBackend() => createProductionBackend(
    openAppService: (directory) => openConfiguredAppService(
      configDirectory: directory,
      surface: BridgeAppServiceSurface.gui,
      release: kReleaseMode,
      readVersion: (widget.appInformation ?? SystemAppInformation()).version,
    ),
  );

  Future<void> _openBackend() async {
    final generation = ++_startupGeneration;
    _updateStartup(() => _startupFailure = null);
    UbaaBackend? opened;
    var stage = DiagnosticInitializationStage.backendOpen;
    try {
      final factory = widget.backendFactory ?? _createBackend;
      opened = await Future<UbaaBackend>.sync(factory);
      if (_disposed || generation != _startupGeneration) {
        if (opened is BackendLifecycle)
          await (opened as BackendLifecycle).dispose();
        return;
      }
      if (opened is UnavailableBackend) {
        throw InitializationException(opened.failure);
      }
      stage = DiagnosticInitializationStage.backendInstall;
      _installBackend(opened);
      _updateStartup(() {});
    } on Object catch (error, stackTrace) {
      if (opened is BackendLifecycle) {
        try {
          await (opened as BackendLifecycle).dispose();
        } on Object {
          /* 保留原始分类。 */
        }
      }
      if (_disposed || generation != _startupGeneration) return;
      _readyController?.dispose();
      _readyController = null;
      _updateStartup(
        () => _startupFailure = (
          error: _recordStartupError(_diagnostics, stage, error, stackTrace),
          stage: stage,
        ),
      );
    }
  }

  Widget _buildStartup() => switch (_startupFailure) {
    null => UbaaBootSplash(themeMode: _themeMode, accent: _accent),
    (:final error, :final stage) => _startupApplication(
      themeMode: _themeMode,
      accent: _accent,
      reportExporter: widget.diagnosticReportExporter,
      openLink: (widget.appInformation ?? SystemAppInformation()).open,
      home: _StartupFailure(
        error: error,
        diagnostics: _diagnostics,
        stage: stage,
        onRetry: () => unawaited(_openBackend()),
      ),
    ),
  };
}

LocalDiagnostics _newStartupDiagnostics(PreferenceValues preferences) =>
    LocalDiagnostics(storage: preferences)
      ..setEnvironment(platform: Platform.operatingSystem);

Future<void> _readDiagnosticVersion(
  LocalDiagnostics diagnostics,
  PlatformAppInformation information, {
  bool Function()? isCurrent,
}) async {
  try {
    final version = await information.version();
    if (isCurrent?.call() ?? true) {
      diagnostics.setEnvironment(appVersion: version);
    }
  } on Object {
    // 版本不可用不影响启动、排障或导出。
  }
}

UiError _recordStartupError(
  LocalDiagnostics diagnostics,
  DiagnosticInitializationStage stage,
  Object error,
  StackTrace stackTrace,
) {
  final safe = error is InitializationException
      ? error
      : const InitializationException(
          InitializationFailure.componentUnavailable,
        );
  return diagnostics.record(
    operation: DiagnosticOperation.initialization,
    initializationStage: stage,
    error: const UiErrorMapper().fromException(safe),
    cause: error,
    stackTrace: stackTrace,
  );
}

Widget _startupApplication({
  required Widget home,
  ThemeMode themeMode = ThemeMode.system,
  UbaaAccent accent = UbaaAccent.blue,
  DiagnosticReportExporter reportExporter = const DiagnosticReportExporter(),
  Future<bool> Function(AppLink)? openLink,
}) => MaterialApp(
  title: 'UBAA',
  locale: UbaaTheme.locale,
  supportedLocales: UbaaTheme.supportedLocales,
  localizationsDelegates: UbaaTheme.localizationsDelegates,
  debugShowCheckedModeBanner: false,
  theme: UbaaTheme.light(accent: accent),
  darkTheme: UbaaTheme.dark(accent: accent),
  themeMode: themeMode,
  builder: (context, child) => UiDiagnosticsScope(
    readRecord: (_) => null,
    exportReport: reportExporter.export,
    exportLabel: reportExporter.supportsSharing ? '分享报告文件' : '保存报告文件',
    openFeedback: openLink == null ? null : () => openLink(AppLink.feedback),
    child: child!,
  ),
  home: home,
);

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({
    required this.error,
    this.onRetry,
    required this.stage,
    required this.diagnostics,
  });
  final UiError error;
  final VoidCallback? onRetry;
  final DiagnosticInitializationStage stage;
  final LocalDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.title),
              const SizedBox(height: 12),
              Text(error.message),
              const SizedBox(height: 12),
              Text(
                '失败阶段：${switch (stage) {
                  DiagnosticInitializationStage.sdk => 'SDK 初始化',
                  DiagnosticInitializationStage.bridgeCheck => 'Bridge 自检',
                  DiagnosticInitializationStage.platformCapabilities => '平台能力初始化',
                  DiagnosticInitializationStage.backendOpen => '打开后端',
                  DiagnosticInitializationStage.backendInstall => '装配应用',
                  DiagnosticInitializationStage.localAccountRestore => '恢复本机账号',
                  DiagnosticInitializationStage.sessionState => '检查会话状态',
                  DiagnosticInitializationStage.credentialRestore => '读取记住的登录资料',
                }}',
              ),
              SelectableText('诊断编号：${error.issueId}'),
              const SizedBox(height: 12),
              if (onRetry != null)
                FilledButton(onPressed: onRetry, child: const Text('重新打开'))
              else
                const Text('请关闭应用后重新打开。'),
              TextButton.icon(
                onPressed: () => uiShowDiagnosticsDialog(
                  context,
                  () => diagnostics.exportText(issueId: error.issueId),
                ),
                icon: const Icon(Icons.description_outlined),
                label: const Text('查看诊断信息'),
              ),
              TextButton(
                onPressed: () =>
                    uiShowDiagnosticsDialog(context, diagnostics.exportText),
                child: const Text('查看诊断历史'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
