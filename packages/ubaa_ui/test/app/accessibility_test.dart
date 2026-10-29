import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/write_harness.dart';
import '../support/navigation.dart';

void _registerResponsiveAccessibilityTests() {
  testWidgets('窄屏动态字体、键盘焦点和全部卡片语义可用', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '${feature.title}已加载',
          details: const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.3),
          ),
          child: coordinatedShell(
            user: const UserSummary(username: 'student', displayName: '测试同学'),
            snapshots: snapshots,
            routePolicy: RoutePolicy.auto,
            activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
            initialDestination: UiDestination.academic,
            telemetryEnabled: false,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Future<void> checkSemantics(List<FeatureId> features) async {
      for (final feature in features) {
        await tester.scrollUntilVisible(
          find.text(feature.title),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.bySemanticsLabel(RegExp('^${feature.title}：')),
          findsOneWidget,
        );
      }
    }

    for (final destination in [
      UiDestination.academic,
      UiDestination.coursework,
      UiDestination.campus,
    ]) {
      await tester.tap(
        find.byKey(ValueKey<String>('tab-${destination.label}')),
      );
      await tester.pumpAndSettle();
      await checkSemantics(destination.features);
    }
    await openFeature(tester, FeatureId.schedule);
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final back = find.byTooltip('返回');
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('tab-学业')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}

void _registerFeatureCardSemanticsTest() {
  testWidgets('功能卡片暴露包含状态和操作提示的无障碍语义', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: feature == FeatureId.schedule
              ? FeatureLoadStatus.success
              : FeatureLoadStatus.idle,
          summary: feature == FeatureId.schedule ? '今日课程' : null,
          details: const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          initialDestination: UiDestination.academic,
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
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

    expect(find.bySemanticsLabel('课表查询：今日课程。点击查看详情'), findsOneWidget);
  });
}

void main() {
  _registerResponsiveAccessibilityTests();
  _registerFeatureCardSemanticsTest();
  _registerLayoutMatrix();
}

void _registerLayoutMatrix() {
  for (final width in <double>[320, 390, 600, 768, 1024, 1440]) {
    for (final scale in <double>[1, 2]) {
      testWidgets('窗口${width}大字$scale可切换全部分组并操作主题', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final changes = <ThemeMode>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: scale == 2 ? UbaaTheme.dark() : UbaaTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: UbaaMainShell(
              user: const UserSummary(username: 'synthetic-layout'),
              snapshots: {
                for (final feature in FeatureId.values)
                  feature: FeatureSnapshot(
                    feature: feature,
                    status: FeatureLoadStatus.empty,
                  ),
              },
              routePolicy: RoutePolicy.auto,
              telemetryEnabled: false,
              onRefresh: () async => fail('布局切换不能刷新'),
              onRetryFeature: (_) async => fail('布局切换不能重新读取'),
              onLogout: () async {},
              onLogoutAndClearAccount: () async {},
              onRoutePolicyChanged: (_) {},
              onTelemetryChanged: (_) {},
              onThemeModeChanged: changes.add,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final destination in UiDestination.values) {
          final Finder target;
          if (width < 600 && destination == UiDestination.settings) {
            await openUtility(tester, '设置');
            expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
            expect(tester.takeException(), isNull);
            continue;
          }
          if (width < 600) {
            target = find.byType(NavigationDestination).at(destination.index);
          } else if (width < 1000) {
            target = find.byTooltip(destination.label);
          } else {
            target = find.widgetWithText(ListTile, destination.label);
          }
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(AppBar, destination.label),
            findsOneWidget,
          );
          final failure = tester.takeException();
          expect(failure, isNull, reason: destination.label);
        }
        final theme = find.byType(SegmentedButton<ThemeMode>);
        await tester.ensureVisible(theme);
        await tester.tap(find.text('深色').last);
        await tester.pumpAndSettle();
        expect(changes, [ThemeMode.dark]);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
