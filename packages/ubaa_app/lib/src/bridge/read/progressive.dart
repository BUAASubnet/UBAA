import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../backend.dart';
import '../context.dart';
import '../features/evaluation/reader.dart' show bridgeBeginEvaluationRead;
import '../features/judge/reader.dart' show bridgeBeginJudgeRead;
import '../features/spoc/reader.dart' show bridgeBeginSpocRead;

Future<FeatureReadTask?> bridgeBeginProgressiveRead(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery? query, {
  LocalAccount? expectedAccount,
}) => feature == FeatureId.evaluation
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
      );
