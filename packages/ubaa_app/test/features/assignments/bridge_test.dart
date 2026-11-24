import 'package:ubaa_app/src/bridge/features/signin/projection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('上课状态分组在缓存与在线一致，未知资格和缺目标仍只读', () {
    final items = [
      for (final status in [0, 1, null])
        BridgeSigninClass(
          courseId: '',
          courseName: '合成$status',
          classBeginTime: '08:00',
          classEndTime: '09:35',
          signStatus: status,
          signinEligibility: BridgeActionEligibility.unknown,
        ),
    ];
    for (final (view, expected) in [
      (FeatureQueryView.summary, ['合成0', '合成1', '合成null']),
      (FeatureQueryView.signinPending, ['合成0']),
      (FeatureQueryView.signinCompleted, ['合成1']),
    ]) {
      for (final persisted in [false, true]) {
        final result = bridgeMapSigninHome(
          items,
          FeatureQuery(view: view),
          ConnectionMode.direct,
          persisted: persisted,
        );
        expect(result.details.map((d) => d.title), expected);
        expect(result.details.expand((d) => d.actions), isEmpty);
      }
    }
  });
}
