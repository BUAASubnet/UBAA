import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
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
            initialDestination: UiDestination.study,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
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
          scrollable: find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          ),
        );
        final card = find.bySemanticsLabel(
          RegExp('^${RegExp.escape(feature.title)}'),
        );
        final data = tester.getSemantics(card).getSemanticsData();
        expect(data.label, contains(snapshots[feature]!.summary));
        expect(data.label, contains('点击查看详情'));
        expect(data.flagsCollection.isButton, isTrue);
      }
    }

    for (final destination in [UiDestination.study, UiDestination.campus]) {
      await tester.tap(
        find.byKey(ValueKey<String>('tab-${destination.label}')),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, 2000),
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
    await tester.tap(find.byKey(const ValueKey<String>('tab-学习')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}

void main() {
  _registerResponsiveAccessibilityTests();
  _registerLayoutMatrix();
}

void _registerLayoutMatrix() {
  for (final (width, scale) in [
    (320.0, 2.0),
    (600.0, 2.0),
    (1024.0, 2.0),
    (390.0, 1.0),
  ]) {
    testWidgets('窗口${width}大字$scale可切换全部分组并操作主题', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
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
              onRefresh: () async => fail('布局切换不能刷新'),
              onRetryFeature: (_) async => fail('布局切换不能重新读取'),
              onLogout: () async {},
              onLogoutAndClearAccount: () async {},
              onRoutePolicyChanged: (_) {},
              appearance: UiAppearanceSettings(onThemeModeChanged: changes.add),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final destination in UiDestination.values) {
          final Finder target;
          if (destination == UiDestination.me ||
              (width < 600 && destination == UiDestination.settings)) {
            await openUtility(tester, destination.label);
            expect(
              find.widgetWithText(AppBar, destination.label),
              findsOneWidget,
            );
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
          if (destination == UiDestination.agenda) {
            final title = find.descendant(
              of: find.byType(AgendaView),
              matching: find.text('日程'),
            );
            expect(title.hitTestable(), findsOneWidget);
            final titleSemantics = tester
                .getSemantics(title)
                .getSemanticsData();
            expect(titleSemantics.label.split('\n'), contains('日程'));
            expect(titleSemantics.flagsCollection.isHeader, isTrue);
            expect(
              tester.widget<AgendaView>(find.byType(AgendaView)).visible,
              isTrue,
            );
          } else {
            expect(
              find.widgetWithText(AppBar, destination.label),
              findsOneWidget,
            );
          }
          final failure = tester.takeException();
          expect(failure, isNull, reason: destination.label);
        }
        final theme = find.byType(SegmentedButton<ThemeMode>);
        await tester.ensureVisible(theme);
        await tester.tap(find.text('深色').last);
        await tester.pumpAndSettle();
        expect(changes, [ThemeMode.dark]);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
