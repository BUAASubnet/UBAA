import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import 'projection.dart' show bridgeMapSigninHome;
import '../../home/reader.dart' show bridgeFinishHomeRefresh;
import '../../support/mapping.dart' show bridgeMapError, bridgeToConnectionMode;

Future<FeatureResult> bridgeLoadSigninHome(
  BridgeContext backend,
  FeatureQuery query, {
  bool useCache = true,
  DateTime Function() currentTime = DateTime.now,
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
    final readDate = homeDateKey(homeCampusTime(currentTime()));
    final value = await backend.client.signinToday();
    // 无缓存读没有持久范围证据，跨校园日期的返回不能重新授予首页动作。
    if (readDate != homeDateKey(homeCampusTime(currentTime()))) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return bridgeMapSigninHome(
      value.data,
      query,
      bridgeToConnectionMode(value.route.resolvedRoute),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}
