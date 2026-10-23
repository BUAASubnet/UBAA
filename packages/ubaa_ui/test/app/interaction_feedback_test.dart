import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('圆角卡片悬停不越出卡片边界', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('卡片区域'),
              child: SizedBox(
                width: 200,
                height: 80,
                child: Card(
                  child: InkWell(
                    onTap: () {},
                    child: const Center(child: Text('座位')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<List<int>> corner() async => (await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('卡片区域')),
          )
          .toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        return bytes.sublist(
          (2 * image.width + 2) * 4,
          (2 * image.width + 2) * 4 + 4,
        );
      } finally {
        image.dispose();
      }
    }))!;
    final before = await corner();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('座位')));
    await tester.pumpAndSettle();
    expect(await corner(), before, reason: '圆角外的像素不应被矩形悬停背景覆盖');
  });

  for (final dark in [false, true]) {
    for (final switchControl in [false, true]) {
      testWidgets('选项行悬停统一且移出恢复：深色=$dark，开关=$switchControl', (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var changes = 0;
        Widget scene({bool enabled = true}) => MaterialApp(
          theme: dark ? UbaaTheme.dark() : UbaaTheme.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: const ValueKey('选项区域'),
                child: SizedBox(
                  width: 360,
                  child: Material(
                    child: switchControl
                        ? SwitchListTile(
                            focusNode: focus,
                            title: const Text('测试选项'),
                            value: false,
                            onChanged: enabled ? (_) => changes++ : null,
                          )
                        : CheckboxListTile(
                            focusNode: focus,
                            title: const Text('测试选项'),
                            value: false,
                            onChanged: enabled ? (_) => changes++ : null,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        Future<List<int>> pixels() async => (await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('选项区域')),
          );
          final image = await boundary.toImage();
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List().toList();
          } finally {
            image.dispose();
          }
        }))!;

        await tester.pumpWidget(scene());
        await tester.pumpAndSettle();
        final idle = await pixels();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('测试选项')));
        await tester.pumpAndSettle();
        final labelHover = await pixels();
        expect(labelHover, isNot(orderedEquals(idle)));
        final control = find.byType(switchControl ? Switch : Checkbox);
        await mouse.moveTo(tester.getCenter(control));
        await tester.pumpAndSettle();
        expect(
          await pixels(),
          orderedEquals(labelHover),
          reason: '控件上不应额外叠加圆形',
        );
        await mouse.down(tester.getCenter(control));
        await mouse.up();
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(changes, 1);
        expect(await pixels(), orderedEquals(idle), reason: '鼠标点击后移出不残留背景');

        final oldStrategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(
          () => FocusManager.instance.highlightStrategy = oldStrategy,
        );
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(await pixels(), isNot(orderedEquals(idle)), reason: '键盘焦点仍可见');
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(changes, 2);
        focus.unfocus();
        await tester.pumpWidget(scene(enabled: false));
        await tester.pumpAndSettle();
        final disabled = await pixels();
        await mouse.moveTo(tester.getCenter(control));
        await mouse.down(tester.getCenter(control));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(changes, 2);
        expect(await pixels(), orderedEquals(disabled));
      });
    }
  }
}
