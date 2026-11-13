import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/shared/layout/page_transition.dart';

void main() {
  testWidgets('进入和返回动画复用静态正文的绘制结果', (tester) async {
    var paints = 0;
    final content = CustomPaint(painter: _PaintCounter(() => paints++));
    Future<void> mount(int page) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UiPageTransition(pageKey: page, order: page, child: content),
        ),
      ),
    );
    await mount(0);
    for (final page in [1, 0]) {
      await mount(page);
      await tester.pump(const Duration(milliseconds: 16));
      final before = paints;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(paints, before, reason: '只有透明度和位置变化时，不重新绘制静态正文');
      await tester.pumpAndSettle();
    }
  });

  testWidgets('切页和切换侧滑能力保留输入状态，减少动态效果时直接显示内容', (tester) async {
    Future<void> mount(int page, bool back, bool reduced) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            body: UiPageTransition(
              pageKey: page,
              order: page,
              onBack: back ? () {} : null,
              child: const TextField(),
            ),
          ),
        ),
      ),
    );
    await mount(0, false, false);
    await tester.enterText(find.byType(TextField), '保留中的输入');
    await mount(1, true, false);
    await tester.pumpAndSettle();
    expect(find.text('保留中的输入'), findsOneWidget);
    await mount(2, false, true);
    await tester.pump();
    expect(find.text('保留中的输入').hitTestable(), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('顺序变大从右侧滑入、变小从左侧滑入，换序列只淡入', (tester) async {
    Future<void> mount(int order, String lane) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UiPageTransition(
            pageKey: (lane, order),
            order: order,
            lane: lane,
            child: const Center(child: Text('正文')),
          ),
        ),
      ),
    );
    await mount(3, '周');
    final rest = tester.getCenter(find.text('正文')).dx;
    Future<double> entering(int order, String lane) async {
      await mount(order, lane);
      await tester.pump(const Duration(milliseconds: 40));
      final dx = tester.getCenter(find.text('正文')).dx - rest;
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('正文')).dx, rest);
      return dx;
    }

    expect(await entering(4, '周'), greaterThan(0));
    expect(await entering(2, '周'), lessThan(0));
    expect(await entering(9, '月'), 0);
  });

  testWidgets('左缘短拖回弹、超过阈值返回，正文水平拖动不触发返回', (tester) async {
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UiPageTransition(
            pageKey: 1,
            order: 1,
            onBack: () => backs++,
            child: const Center(child: Text('详情正文')),
          ),
        ),
      ),
    );
    final original = tester.getCenter(find.text('详情正文'));
    await tester.timedDragFrom(
      const Offset(4, 200),
      const Offset(70, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(backs, 0);
    expect(tester.getCenter(find.text('详情正文')), original);
    await tester.timedDragFrom(
      const Offset(200, 200),
      const Offset(350, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(backs, 0);
    await tester.timedDragFrom(
      const Offset(4, 200),
      const Offset(350, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(backs, 1);
    expect(tester.getCenter(find.text('详情正文')), original);
  });
}

class _PaintCounter extends CustomPainter {
  _PaintCounter(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _PaintCounter oldDelegate) => false;
}
