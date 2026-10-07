import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import '../../assignments/projection.dart' show bridgeToSigninActionEligibility;
import '../../support/mapping.dart' show bridgeCountResult;
part 'home_cache_projection.dart';

FeatureResult bridgeMapSigninHome(
  List<BridgeSigninClass> items,
  FeatureQuery query,
  ConnectionMode route, {
  bool persisted = false,
}) {
  final classes = switch (query.view) {
    FeatureQueryView.summary => items,
    FeatureQueryView.signinPending =>
      items
          .where(
            (item) => (persisted
                ? item.signStatus == 0
                : item.signinEligibility == BridgeActionEligibility.allowed),
          )
          .toList(growable: false),
    FeatureQueryView.signinCompleted =>
      items
          .where(
            (item) => (persisted
                ? item.signStatus == 1
                : item.signinEligibility == BridgeActionEligibility.denied),
          )
          .toList(growable: false),
    _ => throw const BackendException(UbaaErrorCode.invalidInput),
  };
  final details = classes
      .map((item) {
        final eligibility = bridgeToSigninActionEligibility(
          item.signinEligibility,
        );
        final target = item.signinTarget?.trim();
        return FeatureDetail(
          title: item.courseName,
          subtitle: '${item.classBeginTime}–${item.classEndTime}',
          presentation: SigninPresentation(
            courseId: item.courseId,
            classBeginTime: item.classBeginTime,
            classEndTime: item.classEndTime,
            signStatus: item.signStatus,
          ),
          fields: <FeatureField>[
            FeatureField(label: '课程 ID', value: item.courseId),
            FeatureField(
              label: '签到状态',
              value: switch (item.signStatus) {
                0 => '未签到',
                1 => '已签到',
                _ => '状态未知',
              },
            ),
          ],
          actions: target == null || target.isEmpty
              ? const <FeatureAction>[]
              : <FeatureAction>[
                  SigninPerformAction(
                    scheduleId: target,
                    eligibility: eligibility,
                  ),
                ],
        );
      })
      .toList(growable: false);
  return bridgeCountResult(
    classes.length,
    switch (query.view) {
      FeatureQueryView.signinPending => persisted ? '门上次未签到课程' : '门可签到课程',
      FeatureQueryView.signinCompleted => '门已签到课程',
      _ => '门今日签到课程',
    },
    details: details,
    resolvedRoute: route,
  );
}
