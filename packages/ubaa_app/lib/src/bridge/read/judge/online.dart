part of '../../bridge_backend.dart';

Future<FeatureReadTask> _beginOnlineJudgeRead(
  BridgeBackend backend,
  LocalAccount? account,
  FeatureQuery query, {
  CacheMaintenanceFailure? cacheFailure,
}) async {
  final generation = backend._offlineGeneration;
  final keys = switch (query.view) {
    FeatureQueryView.judgeDetail => [
      BridgeJudgeAssignmentKey(
        courseId: _requiredQueryValue(query.courseId, '课程编号'),
        assignmentId: _requiredQueryValue(query.assignmentId, '作业编号'),
      ),
    ],
    FeatureQueryView.judgeBatchDetails => _onlineJudgeKeys(query),
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
      _checkOfflineGeneration(backend, generation);
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
    _checkOfflineGeneration(backend, generation);
    throw _mapError(error);
  }
}

List<BridgeJudgeAssignmentKey> _onlineJudgeKeys(FeatureQuery query) {
  if (query.judgeKeys.isEmpty)
    throw const BackendException(UbaaErrorCode.invalidInput);
  final seen = <(String, String)>{};
  return [
    for (final key in query.judgeKeys)
      if (seen.add((key.courseId, key.assignmentId)))
        BridgeJudgeAssignmentKey(
          courseId: _requiredQueryValue(key.courseId, '课程编号'),
          assignmentId: _requiredQueryValue(key.assignmentId, '作业编号'),
        ),
  ];
}

extension _JudgeOnlineBatchDetails on _JudgeFeatureTask {
  FeatureReadBatch _batchDetails(BridgeJudgeProgress progress) {
    final keys = _onlineJudgeKeys(query);
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
          _judgeDetailPresentation(detail, batch: true),
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
            fetchedAt: _cacheTime(progress.summaryFetchedAt.toInt()),
            complete: progress.batch.complete && warning == null,
            savedForOffline: false,
            cacheFailure: cacheFailure,
          );
    final route = _toConnectionMode(progress.batch.route.resolvedRoute);
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
