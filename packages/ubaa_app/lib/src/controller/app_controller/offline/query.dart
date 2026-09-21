part of '../../app_controller.dart';

extension _AppControllerOfflineQuery on AppController {
  Future<void> _restoreCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    int generation,
    int lifecycle,
    int? ygdkGeneration,
  ) async {
    final backend = _backend;
    final account = _localAccount;
    final policy = _loginForm.routePolicy;
    if (backend is! OfflineQueryBackend || account == null) return;
    bool current() =>
        identical(_backend, backend) &&
        _localAccount?.id == account.id &&
        _loginForm.routePolicy == policy &&
        _isFeatureLoadCurrent(feature, generation, lifecycle, ygdkGeneration);
    try {
      await _offlineOpenFuture;
      if (!current()) return;
      final read = await (backend as OfflineQueryBackend).readCachedQuery(
        feature,
        query,
        policy,
      );
      if (!current()) return;
      final projection = read.projection;
      final previous = _snapshots[feature]!;
      if (projection != null &&
          projection.accountId == account.id &&
          projection.feature == feature &&
          projection.readContext.hasSameQuery(query) &&
          (policy == RoutePolicy.auto ||
              (policy == RoutePolicy.direct &&
                  projection.route == ConnectionMode.direct) ||
              (policy == RoutePolicy.webvpn &&
                  projection.route == ConnectionMode.webvpn)) &&
          (previous.evidence == null ||
              previous.evidence!.origin == DataOrigin.persisted) &&
          previous.status != FeatureLoadStatus.success &&
          previous.status != FeatureLoadStatus.empty) {
        _snapshots[feature] = projection.toSnapshot().copyWith(
          readContext: previous.readContext,
          status: previous.status == FeatureLoadStatus.loading
              ? FeatureLoadStatus.loading
              : FeatureLoadStatus.stale,
          error: previous.error,
        );
      }
      if (read.error != null)
        _localCacheError = _recordFailure(
          read.error!,
          DiagnosticOperation.read,
          feature: feature,
        );
      _notify();
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      _localCacheError = _recordFailure(
        error,
        DiagnosticOperation.read,
        feature: feature,
        stackTrace: stackTrace,
      );
      _notify();
    }
  }
}
