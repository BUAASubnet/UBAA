import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import 'projection.dart' show bridgeJudgeDetailPresentation;
import '../features/judge/reader.dart' show bridgeLoadJudgeWithCache;
import '../features/signin/reader.dart' show bridgeLoadSigninHome;
import '../features/spoc/reader.dart' show bridgeLoadSpocHome;
import '../support/mapping.dart'
    show bridgeRequiredQueryValue, bridgeToConnectionMode;

Future<FeatureResult> bridgeLoadAssignmentFeature(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.spoc:
      return bridgeLoadSpocHome(backend, query);
    case FeatureId.judge:
      switch (query.view) {
        case FeatureQueryView.summary:
          return bridgeLoadJudgeWithCache(
            backend,
            includeExpired: query.includeExpired,
          );
        case FeatureQueryView.judgeDetail:
          final courseId = bridgeRequiredQueryValue(query.courseId, '课程编号');
          final assignmentId = bridgeRequiredQueryValue(
            query.assignmentId,
            '作业编号',
          );
          final result = await client.judgeAssignment(
            courseId: courseId,
            assignmentId: assignmentId,
          );
          return FeatureResult.success(
            summary: '希冀作业详情',
            details: [bridgeJudgeDetailPresentation(result.data)],
            resolvedRoute: bridgeToConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.judgeBatchDetails:
          if (query.judgeKeys.isEmpty) {
            throw const BackendException(UbaaErrorCode.invalidInput);
          }
          final result = await client.judgeAssignmentDetails(
            keys: query.judgeKeys
                .map(
                  (key) => BridgeJudgeAssignmentKey(
                    courseId: key.courseId,
                    assignmentId: key.assignmentId,
                  ),
                )
                .toList(growable: false),
          );
          final details = result.data
              .map((item) => bridgeJudgeDetailPresentation(item, batch: true))
              .toList(growable: false);
          return FeatureResult.success(
            summary: '${result.data.length}项希冀作业详情',
            details: details,
            resolvedRoute: bridgeToConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.signin:
      return bridgeLoadSigninHome(backend, query);
    default:
      throw StateError('unexpected feature: $feature');
  }
}
