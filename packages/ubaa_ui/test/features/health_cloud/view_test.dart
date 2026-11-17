import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/health_cloud/mascot.dart';
import 'package:ubaa_ui/src/features/health_cloud/switches.dart';
import 'package:ubaa_ui/src/features/health_cloud/view.dart';

const latest = HealthCloudYear(2026, '2026-2027_1');
const earlier = HealthCloudYear(2025, '2025-2026_1');

HealthCloudPage page(HealthCloudYear year, double weight) => HealthCloudPage(
  years: const [latest, earlier],
  selectedYear: year.key,
  route: ConnectionMode.direct,
  report: HealthCloudReport(
    weightKg: weight,
    events: const [
      HealthCloudEvent('800米跑', result: '4′18″', score: 64),
      HealthCloudEvent('50米跑', result: '8秒', score: 70),
      HealthCloudEvent('立定跳远'),
      HealthCloudEvent('仰卧起坐', result: '0次', score: 0, grade: '不及格'),
    ],
  ),
);

Future<void> mount(WidgetTester tester, ReadHealthCloud read) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HealthCloudView(read: read)),
      ),
    );

void main() {
  testWidgets('体重的任意一端都能围绕中心对称伸缩', (tester) async {
    await mount(tester, (_) async => page(latest, 68));
    await tester.pumpAndSettle();
    final weight = find.byType(RangeSlider).first;
    final mascot = find.byType(HealthCloudMascot);
    final originalWidth = tester.widget<HealthCloudMascot>(mascot).widthScale;
    final initial = tester.widget<RangeSlider>(weight);
    initial.onChanged!(
      RangeValues(initial.values.start - .08, initial.values.end),
    );
    await tester.pump();
    final wider = tester.widget<RangeSlider>(weight);
    expect(wider.values.start + wider.values.end, closeTo(1, .0001));
    expect(wider.values.end, greaterThan(initial.values.end));
    expect(
      tester.widget<HealthCloudMascot>(mascot).widthScale,
      greaterThan(originalWidth),
    );

    wider.onChanged!(RangeValues(wider.values.start, wider.values.end - .11));
    await tester.pump();
    final narrower = tester.widget<RangeSlider>(weight);
    expect(narrower.values.start + narrower.values.end, closeTo(1, .0001));
    expect(narrower.values.end, lessThan(initial.values.end));
  });

  testWidgets('切换类别和刷新重新读取，临时滑杆值不会覆盖成绩', (tester) async {
    final calls = <String?>[];
    await mount(tester, (year) async {
      calls.add(year);
      return page(latest, 68);
    });
    await tester.pumpAndSettle();
    final weight = find.byType(RangeSlider).first;
    expect(find.text('体重 · 68 kg'), findsOneWidget);
    final slider = tester.widget<RangeSlider>(weight);
    slider.onChanged!(
      RangeValues(slider.values.start - .04, slider.values.end),
    );
    await tester.pump();
    expect(find.text('体重 · 68 kg'), findsNothing);

    await tester.tap(find.byTooltip('运动成绩'));
    await tester.pumpAndSettle();
    expect(find.text('800米跑'), findsOneWidget);
    expect(find.text('4′18″'), findsOneWidget);
    expect(find.text('缺'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('0次'), findsOneWidget);
    final longTitle = tester.getTopLeft(find.text('800米跑'));
    final longScore = tester.getTopLeft(find.text('64'));
    expect(longScore.dx, greaterThan(longTitle.dx));
    expect(longScore.dy, lessThan(tester.getTopLeft(find.text('4′18″')).dy));
    await tester.tap(find.byTooltip('身体指标'));
    await tester.pumpAndSettle();
    expect(find.text('体重 · 68 kg'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新体测成绩'));
    await tester.pumpAndSettle();
    expect(calls, [null, latest.key, latest.key, latest.key]);
  });

  testWidgets('选择轨道保持居中，指标布局随比例调整', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(360, 720);
    await mount(tester, (_) async => page(latest, 68));
    await tester.pumpAndSettle();
    final switches = find.byType(HealthCloudSwitch);
    final mascot = find.byType(HealthCloudMascot);
    final lung = find.text('肺活量 · 缺项');
    expect(tester.getCenter(switches.first).dx, 180);
    expect(tester.getCenter(switches.last).dx, 180);
    expect(
      tester.getTopLeft(lung).dy,
      greaterThan(tester.getBottomRight(mascot).dy),
    );

    tester.view.physicalSize = const Size(1040, 430);
    await tester.pumpAndSettle();
    expect(tester.getCenter(switches.first).dx, 520);
    expect(tester.getCenter(switches.last).dx, 520);
    expect(
      tester.getTopLeft(lung).dx,
      greaterThan(tester.getBottomRight(mascot).dx),
    );

    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(280, 430);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('坐位体前屈 · 缺项'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.byType(ListView))
          .contains(tester.getCenter(find.text('坐位体前屈 · 缺项'))),
      isTrue,
    );
  });

  testWidgets('连续选年份时不接受迟到的成绩', (tester) async {
    final yearRequest = Completer<HealthCloudPage>();
    await mount(tester, (year) {
      return switch (year) {
        null => Future.value(page(latest, 68)),
        '2026-2027_1' => Future.value(page(latest, 69)),
        _ => yearRequest.future,
      };
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025'));
    await tester.pump();
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    yearRequest.complete(page(earlier, 81));
    await tester.pumpAndSettle();
    expect(find.text('体重 · 69 kg'), findsOneWidget);
    expect(find.text('体重 · 81 kg'), findsNothing);
  });

  testWidgets('偏心拖动释放时回弹越过原位并停止', (tester) async {
    await mount(tester, (_) async => page(latest, 68));
    await tester.pumpAndSettle();
    final mascot = find.byType(HealthCloudMascot);
    final transform = find.descendant(
      of: mascot,
      matching: find.byType(Transform),
    );
    final center = tester.getCenter(mascot);
    final gesture = await tester.startGesture(center + const Offset(24, 0));
    await tester.pump(const Duration(milliseconds: 160));
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    final pressed = tester.widget<Transform>(transform).transform.clone();
    expect(pressed.entry(2, 3), greaterThan(0));
    expect(pressed.entry(0, 3), greaterThan(0));
    expect(pressed.entry(2, 0).abs(), greaterThan(.01));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 225));
    final rebound = tester.widget<Transform>(transform).transform;
    expect(rebound.entry(2, 3), lessThan(0));
    expect(rebound.entry(0, 3), lessThan(0));

    await tester.pumpAndSettle();
    final resting = tester.widget<Transform>(transform).transform;
    expect(resting.entry(2, 3), closeTo(0, .12));
    expect(resting.entry(0, 3), closeTo(0, .12));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
