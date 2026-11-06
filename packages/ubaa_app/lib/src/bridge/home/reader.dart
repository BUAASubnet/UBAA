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
  const route = BridgeConnectionMode.direct;
  BackendException? failure;
  Future<T?> readPart<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on BridgeError catch (error) {
      failure ??= bridgeMapError(error);
      return null;
    }
  }

  final today = await readPart(() => cache.readToday(route: route));
  final judge = await readPart(
    () => cache.readJudge(route: route, includeExpired: false),
  );
  final additional = <CachedFeatureProjection>[];
  for (final feature in [
    FeatureId.signin,
    FeatureId.spoc,
    FeatureId.ygdk,
    FeatureId.exam,
  ]) {
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
    if (today != null)
      CachedFeatureProjection(
        feature: FeatureId.schedule,
        accountId: account.id,
        route: bridgeToConnectionMode(today.sourceRoute),
        fetchedAt: bridgeCacheTime(today.fetchedAt.toInt()),
        complete: today.complete,
        scopeDate: today.date,
        details: today.data.map(bridgeTodayDetail),
      ),
    if (judge != null)
      CachedFeatureProjection(
        feature: FeatureId.judge,
        accountId: account.id,
        route: bridgeToConnectionMode(judge.sourceRoute),
        fetchedAt: bridgeCacheTime(judge.fetchedAt.toInt()),
        complete: judge.complete,
        details: bridgeJudgeSummaryDetails(judge.data, includeExpired: false),
      ),
  ], error: failure);
}
