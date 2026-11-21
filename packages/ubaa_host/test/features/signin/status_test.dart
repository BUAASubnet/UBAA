import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_test_support/navigation.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/privacy.dart';

void main() {
  testWidgets('二维码面板经宿主在线查询，签到后关闭并更新课程状态', (tester) {
    return withClock(Clock.fixed(DateTime.utc(2026, 11, 19, 0, 10)), () async {
      final backend = _Backend();
      await tester.pumpWidget(
        UbaaAppHost(
          preferenceValues: acceptedPrivacyPreferences(),
          backend: backend,
          initialDestination: UiDestination.study,
        ),
      );
      await tester.pumpAndSettle();
      await openFeature(tester, FeatureId.signin);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('签到二维码'));
      await tester.pumpAndSettle();
      expect(backend.qrTargets, ['课次']);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(backend.statusReads, 1);
      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      final row = shell.snapshots[FeatureId.signin]!.details.single;
      expect((row.presentation as SigninPresentation).signStatus, 1);
      await tester.pump(const Duration(seconds: 6));
      expect(backend.statusReads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

final class _Backend
    implements UbaaBackend, SigninQrBackend, SigninReadbackBackend {
  int statusReads = 0;
  final qrTargets = <String>[];

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic');
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature == FeatureId.signin ? _result(0) : const FeatureResult.empty();
  @override
  Future<FeatureResult> readSigninAfterWrite() async {
    statusReads++;
    return _result(1);
  }

  @override
  Future<SigninQr> fetchSigninQr(String courseId, Duration offset) async {
    qrTargets.add(courseId);
    return const SigninQr(content: '合成二维码', timestamp: 1700000000000);
  }

  FeatureResult _result(int signStatus) => FeatureResult.success(
    details: [
      FeatureDetail(
        title: '合成课程',
        presentation: SigninPresentation(
          courseId: '课次',
          actionTarget: '课次',
          classBeginTime: '08:00',
          classEndTime: '09:40',
          signStatus: signStatus,
        ),
        actions: [
          SigninPerformAction(
            scheduleId: '课次',
            eligibility: signStatus == 1
                ? ActionEligibility.denied
                : ActionEligibility.allowed,
          ),
        ],
      ),
    ],
  );
}
