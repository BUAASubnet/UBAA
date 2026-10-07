import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import '../../assignments/projection.dart' show bridgeJudgeDetailPresentation;
import 'projection.dart' show bridgeOnlineJudgeKeys;
import '../../support/mapping.dart'
    show bridgeCacheTime, bridgeMapError, bridgeToConnectionMode;

Future<OfflineQueryRead> bridgeReadCachedJudgeBatch(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route,
) async {
  final keys = bridgeOnlineJudgeKeys(query);
  final details = <FeatureDetail>[];
  DateTime? fetchedAt;
  var complete = true;
  BackendException? failure;
  for (final key in keys) {
    try {
      final record = await cache.readJudgeDetail(
        route: route,
        courseId: key.courseId,
        assignmentId: key.assignmentId,
      );
      if (record == null) {
        complete = false;
        continue;
      }
      if (record.sourceRoute != route ||
          record.data.courseId != key.courseId ||
          record.data.assignmentId != key.assignmentId)
        throw const BackendException(
          UbaaErrorCode.internalError,
          cacheFailure: CacheMaintenanceFailure.corrupt,
        );
      details.add(bridgeJudgeDetailPresentation(record.data, batch: true));
      final time = bridgeCacheTime(record.fetchedAt.toInt());
      if (fetchedAt == null || time.isBefore(fetchedAt)) fetchedAt = time;
      complete = complete && record.complete;
    } on BridgeError catch (error) {
      final mapped = bridgeMapError(error);
      if (mapped.cacheFailure == CacheMaintenanceFailure.inactive ||
          mapped.cacheFailure == CacheMaintenanceFailure.superseded ||
          mapped.accountMismatch)
        rethrow;
      failure ??= mapped;
      complete = false;
    } on BackendException catch (error) {
      failure ??= error;
      complete = false;
    }
  }
  return OfflineQueryRead(
    fetchedAt == null
        ? null
        : CachedFeatureProjection(
            feature: FeatureId.judge,
            accountId: account.id,
            route: bridgeToConnectionMode(route),
            query: query,
            fetchedAt: fetchedAt,
            complete: complete,
            details: details,
          ),
    error: failure,
  );
}
