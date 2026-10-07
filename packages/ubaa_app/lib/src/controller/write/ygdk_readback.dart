import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/models.dart' show YgdkReadbackSlot;
import '../state/state.dart' show ControllerState;

/// 阳光打卡后在原路线依次刷新概览与首页记录，不重发写请求。
Future<void> controllerRefreshYgdkAfterWrite(
  ControllerState controller, {
  required ConnectionMode expectedRoute,
}) async {
  if (controller.internalDisposed ||
      controller.internalBackend is! YgdkSubmissionReadbackBackend) {
    return;
  }
  final backend = controller.internalBackend as YgdkSubmissionReadbackBackend;
  final generation = ++controller.internalYgdkGeneration;
  final requestRevision = controller.internalNextFeatureGeneration(
    FeatureId.ygdk,
  );
  controller.internalReadCacheEpoch++;
  controller.internalHomeDefaults[FeatureId.ygdk] = FeatureSnapshot(
    feature: FeatureId.ygdk,
    status: FeatureLoadStatus.loading,
    readContext: FeatureReadContext(
      query: const FeatureQuery(),
      requestRevision: requestRevision,
    ),
  );
  controller.internalNotify();
  if (controller.internalDisposed ||
      generation != controller.internalYgdkGeneration)
    return;

  UiError mapFailure(Object cause, StackTrace? stackTrace) {
    if (controller.internalDisposed ||
        generation != controller.internalYgdkGeneration) {
      return UbaaErrorMapper.fromObject(cause);
    }
    return controller.internalRecordFailure(
      cause,
      DiagnosticOperation.readback,
      feature: FeatureId.ygdk,
      stackTrace: stackTrace,
    );
  }

  final overview = await controllerLoadYgdkReadbackSnapshot(
    readContext: FeatureReadContext(
      query: const FeatureQuery(),
      requestRevision: requestRevision,
    ),
    expectedRoute: expectedRoute,
    mapFailure: mapFailure,
    load: () => backend.loadYgdkOverviewOnRoute(route: expectedRoute),
  );
  final overviewIsCurrent = controllerApplyYgdkReadbackSnapshotIfCurrent(
    controller,
    slot: YgdkReadbackSlot.overview,
    snapshot: overview,
    generation: generation,
  );
  if (!overviewIsCurrent) return;

  final records = await controllerLoadYgdkReadbackSnapshot(
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
  controllerApplyYgdkReadbackSnapshotIfCurrent(
    controller,
    slot: YgdkReadbackSlot.records,
    snapshot: records,
    generation: generation,
  );
}

Future<FeatureSnapshot> controllerLoadYgdkReadbackSnapshot({
  required ConnectionMode expectedRoute,
  required FeatureReadContext readContext,
  required Future<FeatureResult> Function() load,
  required UiError Function(Object, StackTrace?) mapFailure,
}) async {
  try {
    final result = await load();
    if (result.error case final error?) {
      return controllerFailedYgdkReadbackSnapshot(
        mapFailure(error, null),
        readContext,
      );
    }
    if (result.resolvedRoute != expectedRoute) {
      return controllerFailedYgdkReadbackSnapshot(
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
    return controllerFailedYgdkReadbackSnapshot(
      mapFailure(error, stackTrace),
      readContext,
    );
  }
}

FeatureSnapshot controllerFailedYgdkReadbackSnapshot(
  UiError error,
  FeatureReadContext readContext,
) => FeatureSnapshot(
  feature: FeatureId.ygdk,
  readContext: readContext,
  status: FeatureLoadStatus.failure,
  error: error,
  updatedAt: DateTime.now(),
);

bool controllerApplyYgdkReadbackSnapshotIfCurrent(
  ControllerState controller, {
  required YgdkReadbackSlot slot,
  required FeatureSnapshot snapshot,
  required int generation,
}) {
  if (controller.internalDisposed ||
      generation != controller.internalYgdkGeneration) {
    return false;
  }
  final current = controller.internalYgdkReadbackState;
  controller.internalYgdkReadbackState = switch (slot) {
    YgdkReadbackSlot.overview => YgdkReadbackState(
      overview: snapshot,
      records: current.records,
    ),
    YgdkReadbackSlot.records => YgdkReadbackState(
      overview: current.overview,
      records: snapshot,
    ),
  };
  if (slot == YgdkReadbackSlot.overview) {
    controller.internalHomeDefaults[FeatureId.ygdk] = snapshot;
    final currentSnapshot = controller.internalSnapshots[FeatureId.ygdk]!;
    if (snapshot.status != FeatureLoadStatus.failure ||
        currentSnapshot.status == FeatureLoadStatus.loading) {
      controller.internalSnapshots[FeatureId.ygdk] = snapshot;
    }
  }
  controller.internalNotify();
  return !controller.internalDisposed &&
      generation == controller.internalYgdkGeneration;
}
