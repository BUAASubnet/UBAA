part of '../bridge_backend.dart';

Future<FeatureReadTask?> _beginJudgeRead(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery? query, {
  LocalAccount? expectedAccount,
}) async {
  if (feature != FeatureId.judge) return null;
  final selected = query ?? const FeatureQuery();
  if (selected.view != FeatureQueryView.summary &&
      selected.view != FeatureQueryView.judgeDetail &&
      selected.view != FeatureQueryView.judgeBatchDetails)
    return null;
  await _awaitOfflineScope(backend);
  final generation = backend._offlineGeneration;
  final cache = backend._offlineCache;
  final account = expectedAccount ?? backend._offlineAccount;
  if (cache == null ||
      account == null ||
      account.id != backend._offlineAccount?.id) {
    return _beginOnlineJudgeRead(backend, account, selected);
  }
  final detail = selected.view == FeatureQueryView.judgeDetail;
  try {
    final void Function() cancelTask;
    final Future<BridgeJudgeProgress> Function() nextProgress;
    if (selected.view == FeatureQueryView.judgeBatchDetails) {
      final task = await backend.client.beginJudgeDetails(
        cache: cache,
        keys: _onlineJudgeKeys(selected),
      );
      cancelTask = task.cancel;
      nextProgress = () => backend.client.nextJudgeDetails(task: task);
    } else {
      final task = await backend.client.beginJudgeRefresh(
        cache: cache,
        options: BridgeJudgeRefreshOptions(
          includeExpired: selected.includeExpired,
          fullRefresh: selected.fullRefresh,
          currentAssignment: detail
              ? BridgeJudgeAssignmentKey(
                  courseId: _requiredQueryValue(selected.courseId, '课程编号'),
                  assignmentId: _requiredQueryValue(
                    selected.assignmentId,
                    '作业编号',
                  ),
                )
              : null,
          preferredCourse: selected.courseId,
        ),
      );
      cancelTask = task.cancel;
      nextProgress = () => backend.client.nextJudgeRefresh(task: task);
    }
    try {
      _checkOfflineGeneration(backend, generation);
    } catch (_) {
      cancelTask();
      rethrow;
    }
    return _JudgeFallbackTask(
      backend,
      account,
      selected,
      generation,
      delegate: _JudgeFeatureTask(
        backend,
        account,
        selected,
        nextProgress: nextProgress,
        cancelTask: cancelTask,
        persistent: true,
      ),
    );
  } on BridgeError catch (error) {
    _checkOfflineGeneration(backend, generation);
    final failure = _mapError(error);
    if (!_canReadJudgeWithoutStorage(failure)) throw failure;
    return _JudgeFallbackTask(
      backend,
      account,
      selected,
      generation,
      cacheFailure: failure.cacheFailure,
    );
  }
}

final class _JudgeFeatureTask implements FeatureReadTask {
  _JudgeFeatureTask(
    this.backend,
    this.account,
    this.query, {
    required this.nextProgress,
    required this.cancelTask,
    required this.persistent,
    this.cacheFailure,
  }) : generation = backend._offlineGeneration;
  final BridgeBackend backend;
  final int generation;
  final Future<BridgeJudgeProgress> Function() nextProgress;
  final void Function() cancelTask;
  final bool persistent;
  final CacheMaintenanceFailure? cacheFailure;
  final LocalAccount? account;
  final FeatureQuery query;
  final _pending = <(String, String), BridgeJudgeAssignmentIndex>{};
  final _details = <(String, String), BridgeJudgeAssignmentDetail>{};
  UiError? _warning;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    cancelTask();
  }

  @override
  Future<FeatureReadBatch> next() async {
    if (_cancelled)
      throw const BackendException(UbaaErrorCode.operationConflict);
    try {
      _checkOfflineGeneration(backend, generation);
      final progress = await nextProgress();
      _checkOfflineGeneration(backend, generation);
      if (_cancelled)
        throw const BackendException(UbaaErrorCode.operationConflict);
      if (progress.batch.error case final error?)
        _warning ??= UbaaErrorMapper.fromObject(_mapError(error));
      if (query.view == FeatureQueryView.judgeDetail) return _detail(progress);
      if (query.view == FeatureQueryView.judgeBatchDetails)
        return _batchDetails(progress);
      if (progress.batch.kind == BridgeJudgeScanKind.assignments) {
        _pending.removeWhere((key, _) => key.$1 == progress.batch.courseId);
        for (final item in progress.batch.assignments) {
          _pending[(item.courseId, item.assignmentId)] = item;
        }
      }
      for (final item in progress.summaries) {
        _pending.remove((item.courseId, item.assignmentId));
      }
      if (progress.batch.detail case final item?)
        _pending.remove((item.courseId, item.assignmentId));
      if (progress.batch.finished && progress.batch.complete) _pending.clear();
      final details = <FeatureDetail>[
        ..._judgeSummaryDetails(
          progress.summaries,
          includeExpired: query.includeExpired,
        ),
        for (final item in _pending.values)
          FeatureDetail(
            title: item.title,
            subtitle: item.courseName,
            fields: const [FeatureField(label: '状态', value: '详情待更新')],
            readNavigation: FeatureReadNavigation(
              feature: FeatureId.judge,
              query: FeatureQuery(
                view: FeatureQueryView.judgeDetail,
                courseId: item.courseId,
                assignmentId: item.assignmentId,
                includeExpired: query.includeExpired,
              ),
            ),
          ),
      ];
      final evidence = account == null
          ? null
          : DataEvidence(
              accountId: account!.id,
              origin: progress.summaryHasCached
                  ? DataOrigin.mixed
                  : DataOrigin.online,
              fetchedAt: _cacheTime(progress.summaryFetchedAt.toInt()),
              complete: progress.batch.complete,
              cacheFailure:
                  cacheFailure ?? _cacheMaintenanceFailure(progress.saveError),
              savedForOffline:
                  persistent &&
                  progress.batch.complete &&
                  progress.saveError == null,
            );
      final route = _toConnectionMode(progress.batch.route.resolvedRoute);
      final warning = _warning;
      final result = warning != null && details.isEmpty
          ? FeatureResult.failure(warning)
          : warning != null
          ? FeatureResult.partial(
              error: warning,
              summary: '${details.length}项希冀作业，部分范围待更新',
              details: details,
              evidence: evidence,
              resolvedRoute: route,
            )
          : details.isEmpty && progress.batch.finished
          ? FeatureResult.empty(evidence: evidence, resolvedRoute: route)
          : FeatureResult.success(
              summary:
                  '${details.length}项希冀作业${progress.batch.finished ? '' : '，继续更新'}',
              details: details,
              evidence: evidence,
              resolvedRoute: route,
            );
      return FeatureReadBatch(result, finished: progress.batch.finished);
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  FeatureReadBatch _detail(BridgeJudgeProgress progress) {
    final item = progress.batch.detail;
    if (item != null &&
        item.courseId == query.courseId &&
        item.assignmentId == query.assignmentId) {
      return FeatureReadBatch(
        FeatureResult.success(
          summary: '希冀作业详情',
          details: [_judgeDetailPresentation(item)],
          resolvedRoute: _toConnectionMode(progress.batch.route.resolvedRoute),
          evidence: account == null
              ? null
              : DataEvidence(
                  accountId: account!.id,
                  origin: progress.reused
                      ? DataOrigin.persisted
                      : DataOrigin.online,
                  fetchedAt: _cacheTime(
                    (progress.sourceFetchedAt ?? progress.summaryFetchedAt)
                        .toInt(),
                  ),
                  complete: true,
                  cacheFailure:
                      cacheFailure ??
                      _cacheMaintenanceFailure(progress.saveError),
                  savedForOffline: persistent && progress.saveError == null,
                ),
        ),
        finished: true,
      );
    }
    final absent =
        progress.batch.kind == BridgeJudgeScanKind.assignments &&
        progress.batch.courseId == query.courseId &&
        !progress.batch.assignments.any(
          (value) => value.assignmentId == query.assignmentId,
        );
    if (_warning != null || absent || progress.batch.finished) {
      return FeatureReadBatch(
        FeatureResult.failure(
          _warning ?? UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput),
        ),
        finished: true,
      );
    }
    // 当前详情尚未读取时不借其他作业冒充目标；控制器继续保留原页内容。
    return const FeatureReadBatch(
      FeatureResult.success(summary: '正在核实当前作业'),
      finished: false,
      publish: false,
    );
  }
}
