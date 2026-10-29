import 'package:ubaa_ui/src/app/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';

void main() {
  testWidgets('未配置统计服务的生产接线保持关闭并说明不可用', (tester) async {
    await tester.pumpWidget(UbaaAppHost(backend: _Backend()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final profile = tester.widget<ProfileView>(find.byType(ProfileView));
    expect(profile.telemetryAvailable, isFalse);
    expect(profile.telemetryEnabled, isFalse);
    expect(find.widgetWithText(SwitchListTile, '匿名产品改进统计'), findsNothing);
  });
}

class _Backend extends DemoBackend {
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
}
