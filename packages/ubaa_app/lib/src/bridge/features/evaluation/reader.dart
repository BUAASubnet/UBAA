import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart'
    show bridgeAwaitOfflineScope, bridgeCheckOfflineGeneration;
import 'cache.dart' show bridgeCachedEvaluationProjection;
import 'projection.dart'
    show bridgeIsEvaluationCacheQuery, bridgeMapEvaluationResult;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeMapError,
        bridgeToBridgeConnectionMode,
        bridgeToConnectionMode;
part 'cache_read.dart';
part 'progressive.dart';

Future<FeatureResult> bridgeLoadEvaluationOnRoute(
  BridgeContext backend, {
  required ConnectionMode route,
}) async {
  try {
    final result = await backend.client.evaluationAllOnRoute(
      route: bridgeToBridgeConnectionMode(route),
    );
    return bridgeMapEvaluationResult(
      result.data,
      bridgeToConnectionMode(result.pinnedRoute),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<FeatureResult> bridgeLoadEvaluationFeature(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  if (feature != FeatureId.evaluation) {
    throw StateError('unexpected feature: $feature');
  }
  switch (query.view) {
    case FeatureQueryView.summary:
    case FeatureQueryView.evaluationPending:
      final cached = await _loadCachedEvaluationFeature(backend, query);
      if (cached != null) return cached;
      final result = await backend.client.evaluationAll();
      return bridgeMapEvaluationResult(
        result.data,
        bridgeToConnectionMode(result.route.resolvedRoute),
        pendingOnly: query.view == FeatureQueryView.evaluationPending,
      );
    default:
      throw const BackendException(UbaaErrorCode.invalidInput);
  }
}
