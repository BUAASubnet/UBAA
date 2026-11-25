import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('每个功能都有会话恢复目标，杭州空间预约复用研讨室路线', () {
    for (final feature in FeatureId.values) {
      expect(
        () => RecoveryTarget.fromFeature(feature),
        returnsNormally,
        reason: feature.name,
      );
    }
    expect(
      RecoveryTarget.fromFeature(FeatureId.hangzhouCgyy),
      RecoveryTarget.cgyy,
    );
    expect(RecoveryTarget.fromFeature(FeatureId.cgyy), RecoveryTarget.cgyy);
  });
}
