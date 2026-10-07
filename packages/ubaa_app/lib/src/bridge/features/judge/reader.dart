import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../assignments/projection.dart'
    show bridgeJudgeDetailPresentation, bridgeJudgeSummaryDetails;
import '../../cache/lifecycle.dart'
    show bridgeAwaitOfflineScope, bridgeCheckOfflineGeneration;
import 'projection.dart'
    show
        bridgeCanReadJudgeWithoutStorage,
        bridgeJudgeStorageTransition,
        bridgeOnlineJudgeKeys;
import '../../support/mapping.dart'
    show
        bridgeCacheMaintenanceFailure,
        bridgeCacheTime,
        bridgeMapError,
        bridgeRequiredQueryValue,
        bridgeToConnectionMode;
part 'progressive.dart';
part 'online.dart';
part 'fallback.dart';

Future<FeatureResult> bridgeLoadJudgeWithCache(
  BridgeContext backend, {
  required bool includeExpired,
}) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle;
  final account = backend.cache.account;
  final BridgeRoutedJudgeSummaries result;
  DataEvidence? evidence;
  if (cache != null && account != null) {
    final refreshed = await backend.client.judgeAssignmentsCached(
      cache: cache,
      includeExpired: includeExpired,
    );
    result = refreshed.result;
    evidence = DataEvidence(
      accountId: account.id,
      origin: DataOrigin.online,
      fetchedAt: bridgeCacheTime(refreshed.fetchedAt.toInt()),
      complete: true,
      savedForOffline: refreshed.saveError == null,
    );
  } else {
    result = await backend.client.judgeAssignments(
      includeExpired: includeExpired,
    );
  }
  final route = bridgeToConnectionMode(result.route.resolvedRoute);
  return result.data.isEmpty
      ? FeatureResult.empty(resolvedRoute: route, evidence: evidence)
      : FeatureResult.success(
          summary: '${result.data.length}项希冀作业',
          details: bridgeJudgeSummaryDetails(
            result.data,
            includeExpired: includeExpired,
          ),
          resolvedRoute: route,
          evidence: evidence,
        );
}
