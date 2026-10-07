import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'projection.dart' show bridgeMapEvaluationResult;
import '../../support/mapping.dart'
    show bridgeCacheTime, bridgeToConnectionMode;

Future<CachedFeatureProjection?> bridgeCachedEvaluationProjection(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route,
) async {
  final value = await cache.readEvaluation(route: route);
  if (value == null) return null;
  final data = BridgeEvaluationCoursesResponse(
    courses: value.data.courses
        .map(
          (v) => BridgeEvaluationCourse(
            id: v.id,
            kcmc: v.kcmc,
            bpmc: v.bpmc,
            isEvaluated: v.isEvaluated,
            submitEligibility: BridgeActionEligibility.unknown,
            submitTarget: null,
          ),
        )
        .toList(),
    progress: value.data.progress,
  );
  final result = bridgeMapEvaluationResult(
    data,
    bridgeToConnectionMode(value.sourceRoute),
    pendingOnly: query.view == FeatureQueryView.evaluationPending,
  );
  return CachedFeatureProjection(
    feature: FeatureId.evaluation,
    query: query,
    accountId: account.id,
    route: bridgeToConnectionMode(value.sourceRoute),
    fetchedAt: bridgeCacheTime(value.fetchedAt.toInt()),
    complete: value.complete,
    details: result.details,
    overview: result.overview,
  );
}
