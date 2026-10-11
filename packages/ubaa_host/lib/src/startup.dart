part of 'ubaa_app_host.dart';

extension _BackendStartup on _UbaaAppHostState {
  Future<void> _openBackend() async {
    final generation = ++_startupGeneration;
    _updateStartup(() => _startupError = null);
    UbaaBackend? opened;
    try {
      final factory = widget.backendFactory ?? createProductionBackend;
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

  Widget _buildStartup() => MaterialApp(
    title: 'UBAA',
    locale: UbaaTheme.locale,
    supportedLocales: UbaaTheme.supportedLocales,
    localizationsDelegates: UbaaTheme.localizationsDelegates,
    theme: UbaaTheme.light(),
    darkTheme: UbaaTheme.dark(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _startupError != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_startupError!.title),
                    const SizedBox(height: 12),
                    Text(_startupError!.message),
                    const SizedBox(height: 12),
                    SelectableText('诊断编号：${_startupError!.issueId}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => unawaited(_openBackend()),
                      child: const Text('重新打开'),
                    ),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在打开本地数据…'),
                  ],
                ),
        ),
      ),
    ),
  );
}
