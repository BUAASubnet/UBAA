import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import '../../support/mapping.dart' show bridgeRequiredQueryValue;
part 'fallback_data.dart';

List<BridgeJudgeAssignmentKey> bridgeOnlineJudgeKeys(FeatureQuery query) {
  if (query.judgeKeys.isEmpty)
    throw const BackendException(UbaaErrorCode.invalidInput);
  final seen = <(String, String)>{};
  return [
    for (final key in query.judgeKeys)
      if (seen.add((key.courseId, key.assignmentId)))
        BridgeJudgeAssignmentKey(
          courseId: bridgeRequiredQueryValue(key.courseId, '课程编号'),
          assignmentId: bridgeRequiredQueryValue(key.assignmentId, '作业编号'),
        ),
  ];
}
