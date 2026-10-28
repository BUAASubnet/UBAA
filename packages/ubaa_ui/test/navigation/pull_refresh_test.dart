import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';
import 'package:ubaa_ui/src/shared/refresh.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('桌面快捷键沿当前查询刷新：$platform', (tester) async {
      var calls = 0;
      await mount(
        tester,
        FeatureId.exam,
        FeatureLoadStatus.success,
        () async => calls++,
        platform: platform,
      );
      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(calls, 1);
    });
  }
  for (final feature in FeatureId.values) {
    for (final status in [
      FeatureLoadStatus.success,
      FeatureLoadStatus.empty,
      FeatureLoadStatus.failure,
    ]) {
      testWidgets('${feature.title} ${status.name} 移动端下拉沿原刷新入口', (
        tester,
      ) async {
        var calls = 0;
        await mount(tester, feature, status, () async => calls++);
        await tester.dragFrom(const Offset(190, 220), const Offset(0, 330));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('iOS 空内容也能下拉刷新', (tester) async {
    var calls = 0;
    await mount(
      tester,
      FeatureId.exam,
      FeatureLoadStatus.empty,
      () async => calls++,
      platform: TargetPlatform.iOS,
    );
    await tester.dragFrom(const Offset(190, 220), const Offset(0, 330));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('横向表格内纵向下拉可刷新，横向拖动不触发', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToRefresh(
            onRefresh: () async => calls++,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1200,
                height: 500,
                child: ListView(children: const [Text('合成表格')]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(180, 180), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.dragFrom(const Offset(180, 180), const Offset(0, 330));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('内嵌纵向列表下拉不误触整页刷新', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToRefresh(
            onRefresh: () async => calls++,
            child: ListView(
              children: [
                SizedBox(
                  height: 200,
                  child: ListView(children: const [Text('内嵌列表')]),
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(180, 70), const Offset(0, 330));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.dragFrom(const Offset(180, 300), const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('下拉进行中再次下拉只发一次读取', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    await mount(tester, FeatureId.exam, FeatureLoadStatus.success, () {
      calls++;
      return gate.future;
    });
    await tester.dragFrom(const Offset(190, 220), const Offset(0, 330));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.dragFrom(const Offset(190, 220), const Offset(0, 330));
    await tester.pump();
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });
}

Future<void> mount(
  WidgetTester tester,
  FeatureId feature,
  FeatureLoadStatus status,
  Future<void> Function() refresh, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: UbaaMainShell(
        initialDestination: UiDestination.forFeature(feature),
        user: const UserSummary(username: 'synthetic-refresh'),
        snapshots: {
          for (final id in FeatureId.values)
            id: FeatureSnapshot(
              feature: id,
              status: id == feature ? status : FeatureLoadStatus.empty,
              details: id == feature && status == FeatureLoadStatus.success
                  ? const [FeatureDetail(title: '合成短列表')]
                  : const [],
              error: id == feature && status == FeatureLoadStatus.failure
                  ? const UiError(
                      code: UbaaErrorCode.networkError,
                      title: '加载失败',
                      message: '合成失败',
                      retryable: true,
                    )
                  : null,
            ),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (id) {
          expect(id, feature);
          return refresh();
        },
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openFeature(tester, feature);
}
