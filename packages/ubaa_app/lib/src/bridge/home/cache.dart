import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import '../features/signin/projection.dart'
    show bridgeMapSigninHome, bridgeSigninCacheDate;
import '../features/spoc/projection.dart'
    show bridgeMapSpocHome, bridgeMapSpocHomeDetail;
import '../features/ygdk/cache.dart' show bridgeLocalYgdkHomeRecords;
import '../features/ygdk/projection.dart' show bridgeMapYgdkOverviewResult;
import '../support/mapping.dart'
    show bridgeCacheTime, bridgeRequiredQueryValue, bridgeToConnectionMode;

Future<CachedFeatureProjection?> bridgeCachedHomeProjection(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureId feature,
  FeatureQuery query,
  BridgeConnectionMode route,
) async {
  FeatureResult result;
  int fetchedAt;
  bool complete;
  BridgeConnectionMode source;
  String? date;
  switch (feature) {
    case FeatureId.signin:
      final value = await cache.readHomeSignin(route: route);
      if (value == null) return null;
      result = bridgeMapSigninHome(
        value.data
            .map(
              (item) => BridgeSigninClass(
                courseId: item.courseId,
                courseName: item.courseName,
                classBeginTime: item.classBeginTime,
                classEndTime: item.classEndTime,
                signStatus: item.signStatus,
                signinEligibility: BridgeActionEligibility.unknown,
              ),
            )
            .toList(),
        query,
        bridgeToConnectionMode(value.sourceRoute),
        persisted: true,
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
      date = bridgeSigninCacheDate(value.date);
    case FeatureId.spoc:
      if (query.view == FeatureQueryView.spocDetail) {
        final id = bridgeRequiredQueryValue(query.assignmentId, '作业编号');
        final value = await cache.readHomeSpocDetail(
          route: route,
          assignmentId: id,
        );
        if (value == null) return null;
        if (value.data.assignmentId != id)
          throw const BackendException(UbaaErrorCode.internalError);
        result = bridgeMapSpocHomeDetail(
          value.data,
          bridgeToConnectionMode(value.sourceRoute),
        );
        fetchedAt = value.fetchedAt.toInt();
        complete = value.complete;
        source = value.sourceRoute;
      } else {
        final value = await cache.readHomeSpoc(route: route);
        if (value == null) return null;
        result = bridgeMapSpocHome(
          value.data,
          bridgeToConnectionMode(value.sourceRoute),
        );
        fetchedAt = value.fetchedAt.toInt();
        complete = value.complete;
        source = value.sourceRoute;
      }
    case FeatureId.ygdk:
      final value = await cache.readHomeYgdk(route: route);
      if (value == null) return null;
      final data = value.data;
      result = bridgeMapYgdkOverviewResult(
        BridgeYgdkOverview(
          summary: data.summary,
          classifyId: data.classifyId,
          classifyName: data.classifyName,
          defaultItemId: data.defaultItemId,
          defaultItemName: data.defaultItemName,
          items: data.items
              .map(
                (item) => BridgeYgdkItem(
                  itemId: item.itemId,
                  name: item.name,
                  kind: item.kind,
                  sort: item.sort,
                  submitEligibility: BridgeActionEligibility.unknown,
                ),
              )
              .toList(),
        ),
        bridgeToConnectionMode(value.sourceRoute),
        records: await bridgeLocalYgdkHomeRecords(
          cache,
          account,
          query,
          value.sourceRoute,
          data.classifyId,
        ),
      );
      fetchedAt = value.fetchedAt.toInt();
      complete = value.complete;
      source = value.sourceRoute;
    default:
      return null;
  }
  return CachedFeatureProjection(
    feature: feature,
    query: query,
    accountId: account.id,
    route: bridgeToConnectionMode(source),
    fetchedAt: bridgeCacheTime(fetchedAt),
    complete: complete,
    scopeDate: date,
    details: result.details,
    overview: result.overview,
  );
}
