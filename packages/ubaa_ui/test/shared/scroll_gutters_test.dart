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
