import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../assignments/projection.dart' show bridgeJudgeSummaryDetails;
import '../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import '../features/schedule/projection.dart' show bridgeTodayDetail;
import '../features/signin/projection.dart' show bridgeSigninCacheDate;
import '../features/ygdk/cache.dart' show HomeYgdkRead;
import 'cache.dart' show bridgeCachedHomeProjection;
import '../read/cache_query.dart' show bridgeReadCachedQuery;
import '../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeMapError,
        bridgeToBridgeConnectionMode,
        bridgeToConnectionMode;
part 'cache_read.dart';

Future<OfflineHomeRead> bridgeReadCachedHome(
  BridgeContext backend,
  RoutePolicy policy,
) async {
  await bridgeAwaitOfflineScope(backend);
  final cache = backend.cache.handle;
  final account = backend.cache.account;
  if (cache == null || account == null) return OfflineHomeRead(const []);
  final routes = switch (policy) {
    RoutePolicy.direct => [BridgeConnectionMode.direct],
    RoutePolicy.webvpn => [BridgeConnectionMode.webVpn],
    RoutePolicy.auto => [
      BridgeConnectionMode.direct,
      BridgeConnectionMode.webVpn,
    ],
  };
  BridgeCachedToday? newest;
  BridgeCachedJudge? newestJudge;
  BackendException? failure;
  Future<T?> readPart<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on BridgeError catch (error) {
      failure ??= bridgeMapError(error);
      return null;
    }
  }

  for (final route in routes) {
    final record = await readPart(() => cache.readToday(route: route));
    if (record != null &&
        (newest == null || record.fetchedAt.toInt() > newest.fetchedAt.toInt()))
      newest = record;
    final judge = await readPart(
      () => cache.readJudge(route: route, includeExpired: false),
    );
    if (judge != null &&
        (newestJudge == null ||
            judge.fetchedAt.toInt() > newestJudge.fetchedAt.toInt()))
      newestJudge = judge;
  }
  final additional = <CachedFeatureProjection>[];
  for (final feature in [FeatureId.signin, FeatureId.spoc, FeatureId.ygdk]) {
    final read = await bridgeReadCachedQuery(
      backend,
      feature,
      const FeatureQuery(),
      policy,
    );
    failure ??= read.error;
    final value = read.projection;
    if (value != null)
      additional.add(
        CachedFeatureProjection(
          feature: feature,
          accountId: value.accountId,
          route: value.route,
          fetchedAt: value.fetchedAt,
          complete: value.complete,
          scopeDate: value.scopeDate,
          details: value.details,
          overview: value.overview,
        ),
      );
  }
  final bykc = await bridgeReadCachedQuery(
    backend,
    FeatureId.bykc,
    const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
    policy,
  );
  failure ??= bykc.error;
  final cgyy = await bridgeReadCachedQuery(
    backend,
    FeatureId.cgyy,
    const FeatureQuery(view: FeatureQueryView.cgyyOrders),
    policy,
  );
  failure ??= cgyy.error;
  return OfflineHomeRead([
    if (bykc.projection != null) bykc.projection!,
    if (cgyy.projection != null) cgyy.projection!,
    ...additional,
    if (newest != null)
      CachedFeatureProjection(
        feature: FeatureId.schedule,
        accountId: account.id,
        route: bridgeToConnectionMode(newest.sourceRoute),
        fetchedAt: bridgeCacheTime(newest.fetchedAt.toInt()),
        complete: newest.complete,
        scopeDate: newest.date,
        details: newest.data.map(bridgeTodayDetail),
      ),
    if (newestJudge != null)
      CachedFeatureProjection(
        feature: FeatureId.judge,
        accountId: account.id,
        route: bridgeToConnectionMode(newestJudge.sourceRoute),
        fetchedAt: bridgeCacheTime(newestJudge.fetchedAt.toInt()),
        complete: newestJudge.complete,
        details: bridgeJudgeSummaryDetails(
          newestJudge.data,
          includeExpired: false,
        ),
      ),
  ], error: failure);
}
