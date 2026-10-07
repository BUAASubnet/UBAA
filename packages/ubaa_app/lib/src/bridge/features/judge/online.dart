part of 'reader.dart';

Future<FeatureReadTask> _beginOnlineJudgeRead(
  BridgeContext backend,
  LocalAccount? account,
  FeatureQuery query, {
  CacheMaintenanceFailure? cacheFailure,
}) async {
  final generation = backend.cache.generation;
  final keys = switch (query.view) {
    FeatureQueryView.judgeDetail => [
      BridgeJudgeAssignmentKey(
        courseId: bridgeRequiredQueryValue(query.courseId, '课程编号'),
        assignmentId: bridgeRequiredQueryValue(query.assignmentId, '作业编号'),
      ),
    ],
    FeatureQueryView.judgeBatchDetails => bridgeOnlineJudgeKeys(query),
    _ => null,
  };
  try {
    final task = await backend.client.beginJudgeOnline(
      options: BridgeJudgeOnlineOptions(
        includeExpired: query.includeExpired,
        expectedIdentity: account?.username,
        preferredCourse: query.courseId,
        keys: keys,
      ),
    );
    try {
      bridgeCheckOfflineGeneration(backend, generation);
    } catch (_) {
      task.cancel();
      rethrow;
    }
    return _JudgeFeatureTask(
      backend,
      account,
      query,
      persistent: false,
      cacheFailure: cacheFailure,
      cancelTask: task.cancel,
      nextProgress: () async {
        final progress = await backend.client.nextJudgeOnline(task: task);
        // 共用展示投影，不把没有保存错误等同于具备持久保存能力。
        return BridgeJudgeProgress(
          batch: progress.batch,
          summaries: progress.summaries,
          summaryFetchedAt: progress.fetchedAt,
          summaryHasCached: false,
          sourceFetchedAt: progress.fetchedAt,
          reused: false,
          saveError: null,
        );
      },
    );
  } on BridgeError catch (error) {
    bridgeCheckOfflineGeneration(backend, generation);
    throw bridgeMapError(error);
  }
}

extension _JudgeOnlineBatchDetails on _JudgeFeatureTask {
  FeatureReadBatch _batchDetails(BridgeJudgeProgress progress) {
    final keys = bridgeOnlineJudgeKeys(query);
    if (progress.batch.detail case final detail?) {
      if (!keys.any(
        (key) =>
            key.courseId == detail.courseId &&
            key.assignmentId == detail.assignmentId,
      )) {
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      }
      _details[(detail.courseId, detail.assignmentId)] = detail;
    }
    final details = [
      for (final key in keys)
        if (_details[(key.courseId, key.assignmentId)] case final detail?)
          bridgeJudgeDetailPresentation(detail, batch: true),
    ];
    if (details.length != keys.length && progress.batch.finished) {
      _warning ??= UbaaErrorMapper.fromCode(UbaaErrorCode.upstreamChanged);
    }
    final warning = _warning;
    final evidence = account == null
        ? null
        : DataEvidence(
            accountId: account!.id,
            origin: DataOrigin.online,
            fetchedAt: bridgeCacheTime(progress.summaryFetchedAt.toInt()),
            complete: progress.batch.complete && warning == null,
            savedForOffline:
                persistent &&
                progress.batch.complete &&
                warning == null &&
                progress.saveError == null,
            cacheFailure:
                cacheFailure ??
                bridgeCacheMaintenanceFailure(progress.saveError),
          );
    final route = bridgeToConnectionMode(progress.batch.route.resolvedRoute);
    final result = warning != null && details.isEmpty
        ? FeatureResult.failure(warning)
        : warning != null
        ? FeatureResult.partial(
            error: warning,
            summary: '${details.length}项希冀作业详情，部分范围待更新',
            details: details,
            resolvedRoute: route,
            evidence: evidence,
          )
        : FeatureResult.success(
            summary:
                '${details.length}项希冀作业详情${progress.batch.finished ? '' : '，继续更新'}',
            details: details,
            resolvedRoute: route,
            evidence: evidence,
          );
    return FeatureReadBatch(
      result,
      finished: progress.batch.finished,
      publish: details.isNotEmpty || progress.batch.finished,
    );
  }
}
