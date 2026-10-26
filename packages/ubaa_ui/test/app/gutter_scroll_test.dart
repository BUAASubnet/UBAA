import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/profile.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  for (final width in [800.0, 1800.0]) {
    testWidgets('导航栏在宽度$width且内容放得下时不随触摸板回弹', (tester) async {
      await _mount(tester, Size(width, 900));
      final navigation = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final body = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ProfileView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(navigation.position.maxScrollExtent, 0);
      final point = tester.getCenter(find.byType(Scrollable).first);
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomUpdate(point, pan: const Offset(0, 50));
      await gesture.panZoomUpdate(point, pan: const Offset(0, 150));
      await tester.pump();
      expect(navigation.position.pixels, 0);
      expect(body.position.pixels, 0);
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
    });

    testWidgets('导航栏在宽度$width的矮窗口可访问溢出入口且固定设置和关于', (tester) async {
      await _mount(tester, Size(width, 400));
      final navigation = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final settings = width < 1000
          ? find.byTooltip('设置')
          : find.widgetWithText(ListTile, '设置');
      final about = width < 1000
          ? find.byTooltip('关于')
          : find.widgetWithText(ListTile, '关于');
      final settingsRect = tester.getRect(settings);
      final aboutRect = tester.getRect(about);
      expect(navigation.position.maxScrollExtent, greaterThan(0));
      final point = tester.getCenter(find.byType(Scrollable).first);
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomUpdate(point, pan: const Offset(0, -50));
      await gesture.panZoomUpdate(point, pan: const Offset(0, -150));
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(navigation.position.pixels, greaterThan(0));
      expect(
        navigation.position.pixels,
        lessThanOrEqualTo(navigation.position.maxScrollExtent),
      );
      expect(tester.getRect(settings), settingsRect);
      expect(tester.getRect(about), aboutRect);
      final campus = width < 1000
          ? find.byTooltip('校园服务')
          : find.widgetWithText(ListTile, '校园服务');
      await tester.ensureVisible(campus);
      await tester.tap(campus);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '校园服务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('宽屏正文两侧留白与正文使用同一个滚动位置', (tester) async {
    await _mount(tester, const Size(1800, 600));
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

Future<void> _mount(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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
}
