import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('窄屏放大文字仍可展开核对提示且不提供写入确认', (tester) async {
    await mount(tester, width: 360, textScale: 2);
    await tester.tap(find.text('1 次操作结果待核实'));
    await tester.pumpAndSettle();
    expect(find.text('查看相关记录'), findsOneWidget);
    expect(find.text('已核对，移除本机提示'), findsOneWidget);
    expect(find.text('确认提交'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页核对提示保留未知语义，只提供查看和本地移除', (tester) async {
    var dismissed = 0;
    await mount(
      tester,
      dismiss: (_) async {
        dismissed++;
        throw StateError('合成本地故障');
      },
    );
    expect(find.text('1 次操作结果待核实'), findsOneWidget);
    await tester.tap(find.text('1 次操作结果待核实'));
    await tester.pumpAndSettle();
    expect(find.textContaining('WebVPN'), findsWidgets);
    expect(find.textContaining('2026'), findsWidgets);
    expect(find.text('查看相关记录'), findsOneWidget);
    expect(find.text('确认提交'), findsNothing);
    await tester.tap(find.text('已核对，移除本机提示'));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    expect(find.text('提示未能移除，请重试'), findsOneWidget);
    expect(find.text('1 次操作结果待核实'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> mount(
  WidgetTester tester, {
  Future<void> Function(String)? dismiss,
  double width = 900,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: UbaaMainShell(
        user: const UserSummary(username: 'fixture-user'),
        snapshots: {
          for (final feature in FeatureId.values)
            feature: FeatureSnapshot(feature: feature),
        },
        routePolicy: RoutePolicy.direct,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
        writeReadbacks: [
          WriteReadbackHint(
            id: '0123456789abcdef0123456789abcdef',
            operation: WriteOperation.signinPerform,
            route: ConnectionMode.webvpn,
            startedAt: DateTime.utc(2026, 9, 23, 7),
          ),
        ],
        onDismissWriteReadback: dismiss,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
