part of '../../bridge_backend.dart';

Future<GradeScoreBaseline?> _updateGradeScoreBaseline(
  BridgeBackend backend,
  String accountId,
  ConnectionMode route,
  GradeScoreBaseline latest,
  GradeScoreBaseline? legacy,
) => _withOfflineRead(backend, () async {
  await _awaitOfflineScope(backend);
  if (backend._offlineCache == null) {
    throw const BackendException(
      UbaaErrorCode.internalError,
      cacheFailure: CacheMaintenanceFailure.unavailable,
    );
  }
  try {
    final previous = await _managementCache(backend, accountId)
        .updateGradeScoreBaseline(
          route: _toBridgeConnectionMode(route),
          latest: _baselineToBridge(latest),
          legacy: legacy == null ? null : _baselineToBridge(legacy),
        );
    return previous == null
        ? null
        : GradeScoreBaseline(
            termCode: previous.termCode,
            termName: previous.termName,
            scores: List.unmodifiable(
              previous.scores.map(
                (entry) => GradeScoreEntry(
                  key: entry.key,
                  courseName: entry.courseName,
                  courseCode: entry.courseCode,
                  score: entry.score,
                ),
              ),
            ),
          );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
});

BridgeGradeScoreBaseline _baselineToBridge(GradeScoreBaseline value) =>
    BridgeGradeScoreBaseline(
      termCode: value.termCode,
      termName: value.termName,
      scores: value.scores
          .map(
            (entry) => BridgeGradeScoreEntry(
              key: entry.key,
              courseName: entry.courseName,
              courseCode: entry.courseCode,
              score: entry.score,
            ),
          )
          .toList(growable: false),
    );
