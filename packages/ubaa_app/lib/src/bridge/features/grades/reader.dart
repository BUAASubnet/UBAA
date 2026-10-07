import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart'
    show bridgeAwaitOfflineScope, bridgeManagementCache, bridgeWithOfflineRead;
import 'projection.dart' show bridgeBaselineToBridge;
import '../../support/mapping.dart'
    show bridgeMapError, bridgeToBridgeConnectionMode;

Future<GradeScoreBaseline?> bridgeUpdateGradeScoreBaseline(
  BridgeContext backend,
  String accountId,
  ConnectionMode route,
  GradeScoreBaseline latest,
  GradeScoreBaseline? legacy,
) => bridgeWithOfflineRead(backend, () async {
  await bridgeAwaitOfflineScope(backend);
  if (backend.cache.handle == null) {
    throw const BackendException(
      UbaaErrorCode.internalError,
      cacheFailure: CacheMaintenanceFailure.unavailable,
    );
  }
  try {
    final previous = await bridgeManagementCache(backend, accountId)
        .updateGradeScoreBaseline(
          route: bridgeToBridgeConnectionMode(route),
          latest: bridgeBaselineToBridge(latest),
          legacy: legacy == null ? null : bridgeBaselineToBridge(legacy),
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
    throw bridgeMapError(error);
  }
});
