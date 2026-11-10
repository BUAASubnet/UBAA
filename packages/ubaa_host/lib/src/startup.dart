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
    _updateStartup(() => _startupError = null);
    UbaaBackend? opened;
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
      final safe = error is InitializationException
          ? error
          : const InitializationException(
              InitializationFailure.componentUnavailable,
            );
      _updateStartup(
        () => _startupError = _startupDiagnostics.record(
          operation: DiagnosticOperation.initialization,
          error: const UiErrorMapper().fromException(safe),
          cause: safe,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Widget _buildStartup() => _startupError == null
      ? UbaaBootSplash(themeMode: _themeMode)
      : _startupApplication(
          themeMode: _themeMode,
          home: _StartupFailure(
            error: _startupError!,
            onRetry: () => unawaited(_openBackend()),
          ),
        );
}

Widget _startupApplication({
  required Widget home,
  ThemeMode themeMode = ThemeMode.system,
}) => MaterialApp(
  title: 'UBAA',
  locale: UbaaTheme.locale,
  supportedLocales: UbaaTheme.supportedLocales,
  localizationsDelegates: UbaaTheme.localizationsDelegates,
  debugShowCheckedModeBanner: false,
  theme: UbaaTheme.light(),
  darkTheme: UbaaTheme.dark(),
  themeMode: themeMode,
  home: home,
);

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({
    required this.error,
    this.onRetry,
    this.stage,
    this.diagnostics,
  });
  final UiError error;
  final VoidCallback? onRetry;
  final String? stage, diagnostics;

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
              if (stage != null) Text('失败阶段：$stage'),
              SelectableText('诊断编号：${error.issueId}'),
              const SizedBox(height: 12),
              if (onRetry != null)
                FilledButton(onPressed: onRetry, child: const Text('重新打开'))
              else
                const Text('请关闭应用后重新打开。'),
              if (diagnostics != null)
                ExpansionTile(
                  title: const Text('诊断详情'),
                  children: [SelectableText(diagnostics!)],
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
