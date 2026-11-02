import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../backend.dart';
import '../context.dart';
import '../cache/lifecycle.dart' show bridgeWithOfflineRead;
import 'dart:async';
import '../features/evaluation/reader.dart' show bridgeBeginEvaluationRead;
import '../features/judge/reader.dart' show bridgeBeginJudgeRead;
import '../features/spoc/reader.dart' show bridgeBeginSpocRead;

Future<FeatureReadTask?> bridgeBeginProgressiveRead(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery? query, {
  LocalAccount? expectedAccount,
}) async {
  final task = await (feature == FeatureId.evaluation
      ? bridgeBeginEvaluationRead(
          backend,
          query,
          expectedAccount: expectedAccount,
        )
      : feature == FeatureId.spoc
      ? bridgeBeginSpocRead(backend, query, expectedAccount: expectedAccount)
      : bridgeBeginJudgeRead(
          backend,
          feature,
          query,
          expectedAccount: expectedAccount,
        ));
  return task == null ? null : _SharedReadTask(backend, task);
}

final class _SharedReadTask implements FeatureReadTask {
  _SharedReadTask(this.backend, this.delegate)
    : generation = backend.cache.generation;
  final BridgeContext backend;
  final FeatureReadTask delegate;
  final int generation;
  @override
  void cancel() => delegate.cancel();
  @override
  Future<FeatureReadBatch> next() => runZoned(
    () => bridgeWithOfflineRead(backend, delegate.next),
    zoneValues: {backend.cache.scopeKey: generation},
  );
}
