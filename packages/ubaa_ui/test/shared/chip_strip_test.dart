import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/common/chip_strip.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('$platform 的选项通过横向滚动或换行保持可选', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => UiChipStrip(
                children: [
                  for (var i = 0; i < 8; i++)
                    ChoiceChip(
                      label: Text('合成选项 $i'),
                      selected: selected == i,
                      onSelected: (_) => setState(() => selected = i),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final first = find.widgetWithText(ChoiceChip, '合成选项 0');
      final last = find.widgetWithText(ChoiceChip, '合成选项 7');
      if (platform == TargetPlatform.android) {
        expect(tester.getRect(last).left, greaterThan(390));
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(-1000, 0),
        );
        await tester.pumpAndSettle();
      } else {
        expect(
          tester.getRect(last).top,
          greaterThan(tester.getRect(first).bottom),
        );
        expect(tester.getRect(last).right, lessThanOrEqualTo(390));
      }
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(selected, 7);
      expect(tester.widget<ChoiceChip>(last).selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('页面边距内的芯片条在手机上延伸到屏幕边缘', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiChipStrip(
                    bleed: true,
                    children: [
                      for (var i = 0; i < 8; i++)
                        FilterChip(label: Text('合成选项 $i'), onSelected: (_) {}),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // 首个选项仍与页面内容左缘对齐，滑动区域覆盖到屏幕边缘。
    expect(tester.getRect(find.byType(SingleChildScrollView)).left, 0);
    expect(tester.getRect(find.byType(SingleChildScrollView)).right, 390);
    expect(tester.getTopLeft(find.byType(FilterChip).first).dx, 16);
  });
}
