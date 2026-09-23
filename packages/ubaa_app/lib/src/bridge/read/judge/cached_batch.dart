part of '../../bridge_backend.dart';

Future<OfflineQueryRead> _readCachedJudgeBatch(
  BridgeOfflineCache cache,
  LocalAccount account,
  FeatureQuery query,
  BridgeConnectionMode route,
) async {
  final keys = _onlineJudgeKeys(query);
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
      details.add(_judgeDetailPresentation(record.data, batch: true));
      final time = _cacheTime(record.fetchedAt.toInt());
      if (fetchedAt == null || time.isBefore(fetchedAt)) fetchedAt = time;
      complete = complete && record.complete;
    } on BridgeError catch (error) {
      final mapped = _mapError(error);
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
            route: _toConnectionMode(route),
            query: query,
            fetchedAt: fetchedAt,
            complete: complete,
            details: details,
          ),
    error: failure,
  );
}
