import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/shared/scroll_gutters.dart';

Future<void> _mount(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(body: ScrollGutters(maxWidth: 400, child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, Offset point, Offset delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(position: point, scrollDelta: delta),
  );
  await tester.pumpAndSettle();
}

Widget _list(ScrollController controller, {bool reverse = false}) => ListView(
  controller: controller,
  reverse: reverse,
  children: const [SizedBox(height: 2400)],
);

void main() {
  for (final x in [100.0, 700.0]) {
    testWidgets('触摸板在留白$x的拖动与惯性和正文一致', (tester) async {
      final controller = ScrollController(initialScrollOffset: 500);
      addTearDown(controller.dispose);
      await _mount(tester, _list(controller));

      Future<(double, double)> panAt(double x) async {
        controller.jumpTo(500);
        final point = Offset(x, 300);
        final gesture = await tester.startGesture(
          point,
          kind: PointerDeviceKind.trackpad,
        );
        for (var step = 1; step <= 4; step++) {
          await gesture.panZoomUpdate(
            point,
            pan: Offset(0, -40.0 * step),
            timeStamp: Duration(milliseconds: step * 16),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        final dragged = controller.offset;
        await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 80));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final coasted = controller.offset;
        await tester.pumpAndSettle();
        return (dragged, coasted);
      }

      final content = await panAt(400);
      expect(content.$1, greaterThan(500));
      expect(content.$2, greaterThan(content.$1));
      final gutter = await panAt(x);
      expect(gutter.$1, closeTo(content.$1, .01));
      expect(gutter.$2, closeTo(content.$2, .01));
    });
  }

  testWidgets('触摸板手势中切换页面会停止旧目标且不带动新页面', (tester) async {
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var page = 0;
    late StateSetter update;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return IndexedStack(
            index: page,
            children: [_list(first), _list(second)],
          );
        },
      ),
    );
    const point = Offset(100, 300);
    final gesture = await tester.startGesture(
      point,
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomUpdate(point, pan: const Offset(0, -100));
    await gesture.panZoomUpdate(point, pan: const Offset(0, -200));
    expect(first.offset, greaterThan(0));
    final before = first.offset;
    update(() => page = 1);
    await tester.pump();
    await gesture.panZoomUpdate(point, pan: const Offset(0, -300));
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(first.offset, before);
    expect(second.offset, 0);
    final next = await tester.startGesture(
      point,
      kind: PointerDeviceKind.trackpad,
    );
    await next.panZoomUpdate(point, pan: const Offset(0, -100));
    await next.panZoomUpdate(point, pan: const Offset(0, -200));
    await next.panZoomEnd();
    await tester.pumpAndSettle();
    expect(first.offset, before);
    expect(second.offset, greaterThan(0));
  });

  testWidgets('留白处纯横向或缩放手势不移动正文，禁用滚动时纵向手势也不移动', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _mount(tester, _list(controller));
    const point = Offset(100, 300);
    final horizontal = await tester.startGesture(
      point,
      kind: PointerDeviceKind.trackpad,
    );
    await horizontal.panZoomUpdate(point, pan: const Offset(100, 0));
    await horizontal.panZoomUpdate(point, pan: const Offset(200, 0));
    await horizontal.panZoomEnd();
    final pinch = await tester.startGesture(
      point,
      kind: PointerDeviceKind.trackpad,
    );
    await pinch.panZoomUpdate(point, scale: 2);
    await pinch.panZoomEnd();
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    await _mount(
      tester,
      ListView(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
        children: const [SizedBox(height: 2400)],
      ),
    );
    final vertical = await tester.startGesture(
      point,
      kind: PointerDeviceKind.trackpad,
    );
    await vertical.panZoomUpdate(point, pan: const Offset(0, -200));
    await vertical.panZoomEnd();
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('切换页面和返回时只滚动可见导航帧并保留其他位置', (tester) async {
    final parent = ScrollController();
    final detail = ScrollController();
    final other = ScrollController();
    addTearDown(parent.dispose);
    addTearDown(detail.dispose);
    addTearDown(other.dispose);
    var page = 0;
    var frame = 1;
    late StateSetter update;
    await _mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return IndexedStack(
            index: page,
            children: [
              IndexedStack(
                index: frame,
                children: [_list(parent), _list(detail)],
              ),
              _list(other),
            ],
          );
        },
      ),
    );
    await _wheel(tester, const Offset(100, 300), const Offset(0, 90));
    expect(detail.offset, 90);
    expect(parent.offset, 0);
    expect(other.offset, 0);
    update(() => page = 1);
    await tester.pumpAndSettle();
    await _wheel(tester, const Offset(700, 300), const Offset(0, 120));
    expect(other.offset, 120);
    expect(detail.offset, 90);
    update(() {
      page = 0;
      frame = 0;
    });
    await tester.pumpAndSettle();
    await _wheel(tester, const Offset(100, 300), const Offset(0, 60));
    expect(parent.offset, 60);
    expect(detail.offset, 90);
    expect(other.offset, 120);
  });

  testWidgets('侧边驱动主列表且正文内嵌纵向列表和横向表格独立滚动', (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    final horizontal = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    addTearDown(horizontal.dispose);
    await _mount(
      tester,
      Column(
        children: [
          SizedBox(
            height: 100,
            child: ListView(
              controller: horizontal,
              scrollDirection: Axis.horizontal,
              children: const [SizedBox(width: 2400)],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: outer,
              child: Column(
                children: [
                  SizedBox(height: 200, child: _list(inner)),
                  const SizedBox(height: 2400),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await _wheel(tester, const Offset(100, 200), const Offset(0, 60));
    expect(outer.offset, 60);
    expect(inner.offset, 0);
    expect(horizontal.offset, 0);
    await _wheel(tester, const Offset(400, 150), const Offset(0, 80));
    expect(inner.offset, 80);
    expect(outer.offset, 60);
    await _wheel(tester, const Offset(400, 50), const Offset(100, 0));
    expect(horizontal.offset, 100);
    await _wheel(tester, const Offset(700, 200), const Offset(100, 0));
    expect(outer.offset, 60);
    expect(horizontal.offset, 100);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _wheel(tester, const Offset(100, 200), const Offset(0, 80));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(outer.offset, 60);
  });

  testWidgets('反向滚动沿用页面方向且禁用滚动的页面不移动', (tester) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    await _mount(tester, _list(controller, reverse: true));
    await _wheel(tester, const Offset(100, 300), const Offset(0, 80));
    expect(controller.offset, 120);
    await _mount(
      tester,
      ListView(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
        children: const [SizedBox(height: 2400)],
      ),
    );
    final before = controller.offset;
    await _wheel(tester, const Offset(700, 300), const Offset(0, 80));
    expect(controller.offset, before);
    expect(tester.takeException(), isNull);
  });
}
