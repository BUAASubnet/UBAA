import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart'
    show bridgeAwaitOfflineScope, bridgeCheckOfflineGeneration;
import 'projection.dart' show bridgeTodayDetail;
import '../../support/mapping.dart'
    show
        bridgeCacheMaintenanceFailure,
        bridgeCacheTime,
        bridgeMapError,
        bridgeToConnectionMode;
part 'import.dart';

Future<FeatureResult> bridgeLoadTodayWithCache(BridgeContext backend) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle;
  final account = backend.cache.account;
  final BridgeRoutedTodayClasses result;
  DataEvidence? evidence;
  if (cache != null && account != null) {
    final refreshed = await backend.client.scheduleTodayCached(cache: cache);
    result = refreshed.result;
    evidence = DataEvidence(
      accountId: account.id,
      origin: DataOrigin.online,
      fetchedAt: bridgeCacheTime(refreshed.fetchedAt.toInt()),
      complete: true,
      savedForOffline: refreshed.saveError == null,
      scopeDate: refreshed.date,
    );
  } else {
    result = await backend.client.scheduleToday();
  }
  final route = bridgeToConnectionMode(result.route.resolvedRoute);
  return result.data.isEmpty
      ? FeatureResult.empty(resolvedRoute: route, evidence: evidence)
      : FeatureResult.success(
          summary: '${result.data.length}今日课程',
          details: result.data.map(bridgeTodayDetail).toList(growable: false),
          resolvedRoute: route,
          evidence: evidence,
        );
}
