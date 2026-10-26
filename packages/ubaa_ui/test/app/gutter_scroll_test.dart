import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/profile.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('宽屏正文两侧留白与正文使用同一个滚动位置', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light().copyWith(platform: TargetPlatform.macOS),
        home: UbaaMainShell(
          user: const UserSummary(username: 'synthetic'),
          initialDestination: UiDestination.settings,
          snapshots: const {},
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byType(ProfileView),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final bounds = tester.getRect(scrollable);
    expect(bounds.width, UbaaTheme.pageMaxWidth);
    expect(position.maxScrollExtent, greaterThan(240));

    Future<void> wheel(Offset point, double delta) async {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: point, scrollDelta: Offset(0, delta)),
      );
      await tester.pumpAndSettle();
    }

    await wheel(bounds.centerLeft - const Offset(40, 0), 120);
    expect(position.pixels, 120);
    await wheel(bounds.centerRight + const Offset(40, 0), 120);
    expect(position.pixels, 240);
    await wheel(bounds.center, -120);
    expect(position.pixels, 120);
    await wheel(bounds.centerLeft - const Offset(40, 0), -1000);
    expect(position.pixels, 0);
    await wheel(bounds.centerRight + const Offset(40, 0), 100000);
    expect(position.pixels, position.maxScrollExtent);
    expect(tester.takeException(), isNull);
  });
}
