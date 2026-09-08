import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support/navigation.dart';

void main() {
  testWidgets('手机收起查询保留草稿与结果，跨宽度和展开均不读取', (tester) async {
    final queries = <FeatureQuery>[];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'fixture-student'),
          snapshots: {
            for (final id in FeatureId.values)
              id: FeatureSnapshot(
                feature: id,
                status: FeatureLoadStatus.success,
                details: const [FeatureDetail(title: '保留的课程结果')],
              ),
          },
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onFeatureQuery: (_, query) async => queries.add(query),
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
    await openFeature(tester, FeatureId.grades);
    await openQueryPanel(tester);
    final term = find.widgetWithText(TextField, '学期编码');
    await tester.enterText(term, '未应用的学期');
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '课程');
    await tester.showKeyboard(term);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(term, findsNothing);
    expect(find.text('保留的课程结果'), findsOneWidget);
    expect(queries, isEmpty);
    tester.view.physicalSize = const Size(834, 1000);
    await tester.pumpAndSettle();
    expect(term, findsNothing);
    await openQueryPanel(tester);
    expect(tester.widget<TextField>(term).controller!.text, '未应用的学期');
    await closeQueryPanel(tester);
    tester.view.physicalSize = const Size(390, 1000);
    await tester.pumpAndSettle();
    expect(term, findsNothing);
    await openQueryPanel(tester);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(term).controller!.text, '未应用的学期');
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
          .controller!
          .text,
      '课程',
    );
    expect(queries, isEmpty);
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(queries.single.term, '未应用的学期');
    expect(queries.single.view, FeatureQueryView.summary);
    expect(tester.takeException(), isNull);
  });
}
