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
  final requestRevision = controller._nextFeatureGeneration(FeatureId.ygdk);
  controller._readCacheEpoch++;
  controller._notify();
  if (controller._disposed || generation != controller._ygdkGeneration) return;

  UiError mapFailure(Object cause, StackTrace? stackTrace) {
    if (controller._disposed || generation != controller._ygdkGeneration) {
      return UbaaErrorMapper.fromObject(cause);
    }
    return controller._recordFailure(
      cause,
      DiagnosticOperation.readback,
      feature: FeatureId.ygdk,
      stackTrace: stackTrace,
    );
  }

  final overview = await _loadYgdkReadbackSnapshot(
    readContext: FeatureReadContext(
      query: const FeatureQuery(),
      requestRevision: requestRevision,
    ),
    expectedRoute: expectedRoute,
    mapFailure: mapFailure,
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
    readContext: FeatureReadContext(
      query: const FeatureQuery(
        view: FeatureQueryView.ygdkRecords,
        page: 1,
        size: 20,
      ),
      requestRevision: requestRevision,
    ),
    expectedRoute: expectedRoute,
    mapFailure: mapFailure,
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
  required FeatureReadContext readContext,
  required Future<FeatureResult> Function() load,
  required UiError Function(Object, StackTrace?) mapFailure,
}) async {
  try {
    final result = await load();
    if (result.error case final error?) {
      return _failedYgdkReadbackSnapshot(mapFailure(error, null), readContext);
    }
    if (result.resolvedRoute != expectedRoute) {
      return _failedYgdkReadbackSnapshot(
        mapFailure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
          null,
        ),
        readContext,
      );
    }
    return FeatureSnapshot(
      feature: FeatureId.ygdk,
      readContext: readContext,
      status: result.isEmpty
          ? FeatureLoadStatus.empty
          : FeatureLoadStatus.success,
      overview: result.overview,
      summary: result.summary,
      details: List<FeatureDetail>.unmodifiable(result.details),
      resolvedRoute: result.resolvedRoute,
      pagination: result.pagination,
      updatedAt: DateTime.now(),
    );
  } on Object catch (error, stackTrace) {
    return _failedYgdkReadbackSnapshot(
      mapFailure(error, stackTrace),
      readContext,
    );
  }
}

FeatureSnapshot _failedYgdkReadbackSnapshot(
  UiError error,
  FeatureReadContext readContext,
) => FeatureSnapshot(
  feature: FeatureId.ygdk,
  readContext: readContext,
  status: FeatureLoadStatus.failure,
  error: error,
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
