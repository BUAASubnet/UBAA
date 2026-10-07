import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart'
    show bridgeAwaitOfflineScope, bridgeCheckOfflineGeneration;
import 'projection.dart' show bridgeMapSpocHome, bridgeMapSpocHomeDetail;
import '../../home/projection.dart' show bridgeIsHomeCacheQuery;
import '../../home/reader.dart' show bridgeFinishHomeRefresh;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeMapError,
        bridgeRequiredQueryValue,
        bridgeToConnectionMode;
part 'progressive.dart';
part 'detail.dart';

Future<FeatureResult> bridgeLoadSpocHome(
  BridgeContext backend,
  FeatureQuery query,
) async {
  if (!bridgeIsHomeCacheQuery(FeatureId.spoc, query))
    throw const BackendException(UbaaErrorCode.invalidInput);
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle, account = backend.cache.account;
  if (query.view == FeatureQueryView.spocDetail) {
    final id = bridgeRequiredQueryValue(query.assignmentId, '作业编号');
    if (cache != null && account != null) {
      final value = await backend.client.homeSpocDetailCached(
        cache: cache,
        assignmentId: id,
      );
      return bridgeFinishHomeRefresh(
        backend,
        cache,
        account,
        FeatureId.spoc,
        query,
        bridgeMapSpocHomeDetail(
          value.result.data,
          bridgeToConnectionMode(value.result.route.resolvedRoute),
        ),
        value.state,
      );
    }
    final value = await backend.client.spocAssignment(assignmentId: id);
    return bridgeMapSpocHomeDetail(
      value.data,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  }
  if (cache != null && account != null) {
    final value = await backend.client.homeSpocCached(cache: cache);
    return bridgeFinishHomeRefresh(
      backend,
      cache,
      account,
      FeatureId.spoc,
      query,
      bridgeMapSpocHome(
        value.result.data,
        bridgeToConnectionMode(value.result.route.resolvedRoute),
      ),
      value.state,
    );
  }
  final value = await backend.client.spocAssignments();
  return bridgeMapSpocHome(
    value.data,
    bridgeToConnectionMode(value.route.resolvedRoute),
  );
}
