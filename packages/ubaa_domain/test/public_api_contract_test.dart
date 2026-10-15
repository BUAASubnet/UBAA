import 'package:test/test.dart';
import 'package:ubaa_domain/src/write/state.dart' as write_state;
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('关键领域对象保持 barrel 类型身份', () {
    expect(WritePhase, same(write_state.WritePhase));
    expect(WriteState, same(write_state.WriteState));
    expect(WriteOutcome, same(write_state.WriteOutcome));
  });

  test('公开枚举与功能常量保持封闭顺序', () {
    expect(RoutePolicy.values, <RoutePolicy>[
      RoutePolicy.auto,
      RoutePolicy.direct,
      RoutePolicy.webvpn,
    ]);
    expect(FeatureId.values, hasLength(12));
    expect(FeatureId.values.first, FeatureId.schedule);
    expect(FeatureId.values.last, FeatureId.evaluation);
    expect(UbaaErrorCode.values, hasLength(16));
    expect(UbaaErrorCode.values.first, UbaaErrorCode.invalidInput);
    expect(UbaaErrorCode.values.last, UbaaErrorCode.outcomeUnknown);
    expect(FeatureLoadStatus.values, <FeatureLoadStatus>[
      FeatureLoadStatus.idle,
      FeatureLoadStatus.loading,
      FeatureLoadStatus.success,
      FeatureLoadStatus.empty,
      FeatureLoadStatus.stale,
      FeatureLoadStatus.failure,
    ]);
    expect(FeatureQueryView.values, hasLength(29));
    expect(FeatureQueryView.values.first, FeatureQueryView.summary);
    expect(FeatureQueryView.values.last, FeatureQueryView.judgeBatchDetails);
    expect(ConnectionMode.values, <ConnectionMode>[
      ConnectionMode.direct,
      ConnectionMode.webvpn,
    ]);
    expect(WriteOperation.values, hasLength(10));
    expect(WriteOperation.values.first, WriteOperation.bykcSelectCourse);
    expect(WriteOperation.values.last, WriteOperation.evaluationSubmitCourses);
    expect(WritePhase.values, <WritePhase>[
      WritePhase.idle,
      WritePhase.preparing,
      WritePhase.ready,
      WritePhase.cancelling,
      WritePhase.committing,
      WritePhase.readingBack,
      WritePhase.invalidating,
    ]);

    expect(ordinaryFeatureIds, <FeatureId>[
      FeatureId.schedule,
      FeatureId.exam,
      FeatureId.grades,
      FeatureId.bykc,
      FeatureId.classroom,
      FeatureId.spoc,
      FeatureId.judge,
      FeatureId.libbook,
    ]);
    expect(advancedFeatureIds, <FeatureId>[
      FeatureId.signin,
      FeatureId.cgyy,
      FeatureId.ygdk,
      FeatureId.evaluation,
    ]);
  });
}
