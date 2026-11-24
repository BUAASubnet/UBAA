import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('首页续借提示直接打开待还图书', (tester) async {
    await mount(tester, operation: WriteOperation.libraryLoanRenew);
    await tester.tap(find.text('1 项操作需要你确认结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去查看'));
    await tester.pumpAndSettle();
    expect(find.text('暂无待还图书'), findsOneWidget);
  });
  testWidgets('展开提示不计打开，去查看上课只计一次', (tester) async {
    final opened = <String>[];
    await mount(tester, onOpened: opened.add);
    await tester.tap(find.text('1 项操作需要你确认结果'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tap(find.text('去查看'));
    await tester.pump();
    expect(opened, ['signin']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('窄屏放大文字仍可展开核对提示且不提供写入确认', (tester) async {
    await mount(tester, width: 360, textScale: 2);
    await tester.tap(find.text('1 项操作需要你确认结果'));
    await tester.pumpAndSettle();
    expect(find.text('去查看'), findsOneWidget);
    expect(find.text('已确认，关闭提醒'), findsOneWidget);
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
    expect(find.text('1 项操作需要你确认结果'), findsOneWidget);
    await tester.tap(find.text('1 项操作需要你确认结果'));
    await tester.pumpAndSettle();
    expect(find.textContaining('WebVPN'), findsWidgets);
    expect(find.textContaining('2026'), findsWidgets);
    expect(find.text('去查看'), findsOneWidget);
    expect(find.text('确认提交'), findsNothing);
    await tester.tap(find.text('已确认，关闭提醒'));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    expect(find.text('没能关闭提醒，请重试'), findsOneWidget);
    expect(find.text('1 项操作需要你确认结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> mount(
  WidgetTester tester, {
  WriteOperation operation = WriteOperation.signinPerform,
  Future<void> Function(String)? dismiss,
  ValueChanged<String>? onOpened,
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
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        writeReadbacks: [
          WriteReadbackHint(
            id: '0123456789abcdef0123456789abcdef',
            operation: operation,
            route: ConnectionMode.webvpn,
            startedAt: DateTime.utc(2026, 9, 23, 7),
          ),
        ],
        onDismissWriteReadback: dismiss,
        readLibraryLoans: () async => [],
        onFeatureOpened: onOpened,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
