part of '../app_controller.dart';

enum _YgdkReadbackSlot { overview, records }

/// 阳光打卡后在原路线依次刷新概览与首页记录，不重发写请求。
Future<void> _refreshYgdkAfterWrite(
  AppController controller, {
  required ConnectionMode expectedRoute,
}) async {
  if (controller._disposed ||
      controller._backend is! YgdkSubmissionReadbackBackend) {
    return;
  }
  final backend = controller._backend as YgdkSubmissionReadbackBackend;
  final generation = ++controller._ygdkGeneration;

  final overview = await _loadYgdkReadbackSnapshot(
    expectedRoute: expectedRoute,
    load: () => backend.loadYgdkOverviewOnRoute(route: expectedRoute),
  );
  final overviewIsCurrent = _applyYgdkReadbackSnapshotIfCurrent(
    controller,
    slot: _YgdkReadbackSlot.overview,
    snapshot: overview,
    generation: generation,
  );
  if (!overviewIsCurrent) return;

  final records = await _loadYgdkReadbackSnapshot(
    expectedRoute: expectedRoute,
    load: () =>
        backend.loadYgdkRecordsOnRoute(route: expectedRoute, page: 1, size: 20),
  );
  _applyYgdkReadbackSnapshotIfCurrent(
    controller,
    slot: _YgdkReadbackSlot.records,
    snapshot: records,
    generation: generation,
  );
}

Future<FeatureSnapshot> _loadYgdkReadbackSnapshot({
  required ConnectionMode expectedRoute,
  required Future<FeatureResult> Function() load,
}) async {
  try {
    final result = await load();
    if (result.error case final error?) {
      return _failedYgdkReadbackSnapshot(error.code);
    }
    if (result.resolvedRoute != expectedRoute) {
      return _failedYgdkReadbackSnapshot(UbaaErrorCode.operationConflict);
    }
    return FeatureSnapshot(
      feature: FeatureId.ygdk,
      status: result.isEmpty
          ? FeatureLoadStatus.empty
          : FeatureLoadStatus.success,
      summary: result.summary,
      details: List<FeatureDetail>.unmodifiable(result.details),
      resolvedRoute: result.resolvedRoute,
      pagination: result.pagination,
      updatedAt: DateTime.now(),
    );
  } on BackendException catch (error) {
    return _failedYgdkReadbackSnapshot(error.code);
  } on Object {
    return _failedYgdkReadbackSnapshot(UbaaErrorCode.internalError);
  }
}

FeatureSnapshot _failedYgdkReadbackSnapshot(UbaaErrorCode code) =>
    FeatureSnapshot(
      feature: FeatureId.ygdk,
      status: FeatureLoadStatus.failure,
      error: UbaaErrorMapper.fromCode(code),
      updatedAt: DateTime.now(),
    );

bool _applyYgdkReadbackSnapshotIfCurrent(
  AppController controller, {
  required _YgdkReadbackSlot slot,
  required FeatureSnapshot snapshot,
  required int generation,
}) {
  if (controller._disposed || generation != controller._ygdkGeneration) {
    return false;
  }
  final current = controller._ygdkReadbackState;
  controller._ygdkReadbackState = switch (slot) {
    _YgdkReadbackSlot.overview => YgdkReadbackState(
      overview: snapshot,
      records: current.records,
    ),
    _YgdkReadbackSlot.records => YgdkReadbackState(
      overview: current.overview,
      records: snapshot,
    ),
  };
  if (slot == _YgdkReadbackSlot.overview) {
    final currentSnapshot = controller._snapshots[FeatureId.ygdk]!;
    if (snapshot.status != FeatureLoadStatus.failure ||
        currentSnapshot.status == FeatureLoadStatus.loading) {
      controller._snapshots[FeatureId.ygdk] = snapshot;
    }
  }
  controller._notify();
  return !controller._disposed && generation == controller._ygdkGeneration;
}
