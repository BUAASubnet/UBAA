import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import 'projection.dart' show bridgeMapSigninHome;
import '../../home/reader.dart' show bridgeFinishHomeRefresh;
import '../../support/mapping.dart' show bridgeMapError, bridgeToConnectionMode;

Future<FeatureResult> bridgeLoadSigninHome(
  BridgeContext backend,
  FeatureQuery query, {
  bool useCache = true,
}) async {
  try {
    if (useCache) await bridgeAwaitOfflineScope(backend);
    final cache = useCache ? backend.cache.handle : null;
    final account = useCache ? backend.cache.account : null;
    if (cache != null && account != null) {
      final value = await backend.client.homeSigninCached(cache: cache);
      return bridgeFinishHomeRefresh(
        backend,
        cache,
        account,
        FeatureId.signin,
        query,
        bridgeMapSigninHome(
          value.result.data,
          query,
          bridgeToConnectionMode(value.result.route.resolvedRoute),
        ),
        value.state,
      );
    }
    final value = await backend.client.signinToday();
    return bridgeMapSigninHome(
      value.data,
      query,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}
