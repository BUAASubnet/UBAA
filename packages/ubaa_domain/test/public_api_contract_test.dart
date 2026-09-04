import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('公共 barrel 保持三十八个稳定名字', () {
    // 公开面精确由 31 个类型、5 个 named extension 和 2 个常量组成。
    final publicTypes = <Type>{
      RoutePolicy,
      FeatureId,
      UbaaErrorCode,
      UiError,
      LoginInput,
      UserSummary,
      FeatureLoadStatus,
      FeatureQueryView,
      FeatureSnapshot,
      FeaturePagination,
      FeatureResult,
      JudgeAssignmentQueryKey,
      FeatureQuery,
      FeatureDetail,
      FeatureField,
      ActionEligibility,
      FeatureAction,
      BykcSelectAction,
      BykcDeselectAction,
      BykcSignKind,
      BykcSignAction,
      YgdkPhotoInput,
      YgdkSubmitInput,
      CgyyReservationSelectionInput,
      CgyySubmitInput,
      EvaluationCourseInput,
      ConnectionMode,
      WriteOperation,
      WriteIntent,
      CgyyReservationReceipt,
      WriteCommitResult,
    };
    expect(publicTypes, hasLength(31));

    expect(RoutePolicyText(RoutePolicy.direct).wireName, 'direct');
    expect(FeatureIdText(FeatureId.schedule).title, '课表查询');
    expect(
      UbaaErrorCodeText(UbaaErrorCode.invalidInput).wireName,
      'invalid_input',
    );
    expect(ConnectionModeText(ConnectionMode.webvpn).label, 'WebVPN');
    expect(WriteOperationText(WriteOperation.signinPerform).title, '课堂签到');

    const ordinary = ordinaryFeatureIds;
    const advanced = advancedFeatureIds;
    expect(ordinary, hasLength(8));
    expect(advanced, hasLength(4));
  });

  test('关键领域对象保持 barrel 类型身份', () {
    const query = FeatureQuery(view: FeatureQueryView.scheduleToday);
    const result = FeatureResult.success(summary: '脱敏摘要');
    const receipt = CgyyReservationReceipt(orderId: 42);

    expect(query.runtimeType, FeatureQuery);
    expect(result.runtimeType, FeatureResult);
    expect(receipt.runtimeType, CgyyReservationReceipt);
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
