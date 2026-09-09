part of '../app_controller.dart';

final class _CgyyPurposeCache {
  _CgyyPurposeCache(this.backend, this.lifecycle, this.epoch);
  final UbaaBackend backend;
  final int lifecycle, epoch;
  final completer = Completer<FeatureResult>();
  bool pending = true;
}

extension _AppControllerCgyyPurposes on AppController {
  bool _purposesCurrent(_CgyyPurposeCache cache) =>
      !_disposed &&
      _writeTransitions == 0 &&
      _phase == AppPhase.home &&
      identical(_cgyyPurposeCache, cache) &&
      identical(cache.backend, _backend) &&
      cache.lifecycle == _lifecycleEpoch &&
      cache.epoch == _readCacheEpoch;

  Future<FeatureResult> _loadCgyyPurposes({required bool forceRefresh}) {
    final UbaaErrorCode? error = _disposed || _writeTransitions != 0
        ? UbaaErrorCode.operationConflict
        : _phase != AppPhase.home
        ? UbaaErrorCode.authenticationRequired
        : _backend is! FeatureQueryBackend
        ? UbaaErrorCode.unsupported
        : null;
    if (error != null)
      return Future.value(
        FeatureResult.failure(UbaaErrorMapper.fromCode(error)),
      );
    final previous = _cgyyPurposeCache;
    if (previous != null &&
        _purposesCurrent(previous) &&
        (previous.pending || !forceRefresh)) {
      return previous.completer.future;
    }
    final cache = _CgyyPurposeCache(_backend, _lifecycleEpoch, _readCacheEpoch);
    _cgyyPurposeCache = cache;
    unawaited(_fetchCgyyPurposes(cache));
    return cache.completer.future;
  }

  Future<void> _fetchCgyyPurposes(_CgyyPurposeCache cache) async {
    FeatureResult result;
    try {
      result = await (cache.backend as FeatureQueryBackend).loadFeatureQuery(
        FeatureId.cgyy,
        const FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes),
      );
      if (!_purposesCurrent(cache)) {
        result = FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
        );
      } else if (result.error case final error?) {
        result = FeatureResult.failure(
          _recordFailure(
            error,
            DiagnosticOperation.read,
            feature: FeatureId.cgyy,
          ),
        );
      } else {
        result = result.isEmpty
            ? FeatureResult.empty(resolvedRoute: result.resolvedRoute)
            : FeatureResult.success(
                summary: result.summary,
                resolvedRoute: result.resolvedRoute,
                details: List.unmodifiable(
                  result.details.map(
                    (detail) => FeatureDetail(
                      title: detail.title,
                      subtitle: detail.subtitle,
                      fields: List.unmodifiable(detail.fields),
                      presentation: detail.presentation,
                    ),
                  ),
                ),
              );
      }
    } on Object catch (error, stackTrace) {
      result = FeatureResult.failure(
        _purposesCurrent(cache)
            ? _recordFailure(
                error,
                DiagnosticOperation.read,
                stackTrace: stackTrace,
                feature: FeatureId.cgyy,
              )
            : UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
      );
    }
    cache.pending = false;
    if (result.error != null && identical(_cgyyPurposeCache, cache))
      _cgyyPurposeCache = null;
    cache.completer.complete(result);
  }
}
