part of '../../app_controller.dart';

extension _AppControllerLocalReadOptions on AppController {
  Future<FeatureResult> _localFirstOptions(
    FeatureQuery query,
    bool forceRefresh,
    Future<FeatureResult> Function() read, {
    FeatureId feature = FeatureId.schedule,
  }) {
    final online = read();
    if (forceRefresh ||
        _backend is! OfflineQueryBackend ||
        _localAccount == null)
      return online;
    final backend = _backend;
    final account = _localAccount!;
    final lifecycle = _lifecycleEpoch, epoch = _readCacheEpoch;
    final policy = _loginForm.routePolicy;
    bool current() =>
        !_disposed &&
        !_isSigningOut &&
        _phase == AppPhase.home &&
        identical(backend, _backend) &&
        lifecycle == _lifecycleEpoch &&
        epoch == _readCacheEpoch &&
        _localAccount?.id == account.id &&
        policy == _loginForm.routePolicy;
    Future<FeatureResult?> localRead() async {
      try {
        await _offlineOpenFuture;
        if (!current()) return null;
        final read = await (backend as OfflineQueryBackend).readCachedQuery(
          feature,
          query,
          policy,
        );
        if (!current()) return null;
        if (read.error != null)
          _localCacheError = _recordFailure(
            read.error!,
            DiagnosticOperation.read,
            feature: feature,
          );
        final value = read.projection;
        if (value == null ||
            value.accountId != account.id ||
            value.feature != feature ||
            !value.readContext.hasSameQuery(query) ||
            (policy == RoutePolicy.direct &&
                value.route != ConnectionMode.direct) ||
            (policy == RoutePolicy.webvpn &&
                value.route != ConnectionMode.webvpn))
          return null;
        final snapshot = value.toSnapshot();
        return snapshot.details.isEmpty
            ? FeatureResult.empty(
                resolvedRoute: snapshot.resolvedRoute,
                evidence: snapshot.evidence,
              )
            : FeatureResult.success(
                details: snapshot.details,
                resolvedRoute: snapshot.resolvedRoute,
                evidence: snapshot.evidence,
              );
      } on Object catch (error, stackTrace) {
        if (current())
          _localCacheError = _recordFailure(
            error,
            DiagnosticOperation.read,
            feature: feature,
            stackTrace: stackTrace,
          );
        return null;
      }
    }

    final local = localRead();
    // 在线任务继续更新原内存与持久范围；只读选项不需要等它完成。
    return Future.any([
      local.then((value) => value ?? online),
      online.then(
        (value) async => value.error == null ? value : await local ?? value,
      ),
    ]);
  }
}
