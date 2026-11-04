import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support.dart';

void main() {
  testWidgets('校园入口与我的云盘空间指标打开同一云盘服务', (tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final files = Files();
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'synthetic'),
          initialDestination: UiDestination.campus,
          bhpanService: files,
          snapshots: {
            for (final id in FeatureId.values)
              id: FeatureSnapshot(feature: id, status: FeatureLoadStatus.empty),
          },
          routePolicy: RoutePolicy.direct,
          telemetryEnabled: false,
          activeRoutes: const [ConnectionMode.direct],
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
    await tester.tap(find.text('北航云盘'));
    await tester.pumpAndSettle();
    expect(find.text('报告.txt'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.me.index),
    );
    await tester.pumpAndSettle();
    final metric = find.byKey(const ValueKey('me-metric-cloud'));
    await tester.ensureVisible(metric);
    await tester.tap(metric);
    await tester.pumpAndSettle();
    expect(find.text('报告.txt'), findsOneWidget);
    expect(
      files.reads.where((q) => q.view == BhpanReadView.personalRoot).length,
      2,
    );
  });
}
