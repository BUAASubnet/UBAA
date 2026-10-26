import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  for (final width in [360.0, 1400.0]) {
    testWidgets('浮动反馈在 $width 宽度下换行并允许关闭', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (value) {
                context = value;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      UbaaFeedback.show(
        context,
        '操作结果尚未核实，请刷新课程列表后确认，避免重复提交。',
        kind: UbaaFeedbackKind.warning,
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(
        find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Material &&
                    widget.shape is RoundedRectangleBorder,
              ),
            )
            .first,
      );
      expect(bounds.width, lessThanOrEqualTo(420));
      expect(bounds.left, greaterThanOrEqualTo(16));
      expect(bounds.right, lessThanOrEqualTo(width - 16));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('新反馈替换旧反馈，成功提示到时退出且不积压消息', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    UbaaFeedback.show(context, '第一项结果');
    await tester.pumpAndSettle();
    UbaaFeedback.show(context, '第二项结果', kind: UbaaFeedbackKind.success);
    await tester.pumpAndSettle();
    expect(find.text('第一项结果'), findsNothing);
    expect(find.text('第二项结果'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(SnackBar), findsNothing);
  });
}
