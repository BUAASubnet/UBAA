import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/shared/loading.dart';

void main() {
  testWidgets('页面加载占位只向标题栏报告忙碌，不在内容区转圈', (tester) async {
    final busy = UiBusyRegistry();
    addTearDown(busy.dispose);
    Widget mount({required bool visible, bool placeholder = true}) =>
        MaterialApp(
          home: UiBusyScope(
            busy: busy,
            child: TickerMode(
              enabled: visible,
              child: Scaffold(
                body: placeholder
                    ? const LoadingPlaceholder(compact: true)
                    : const SizedBox(),
              ),
            ),
          ),
        );

    await tester.pumpWidget(mount(visible: true));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    expect(busy.busy, isTrue);

    // 页面被切到后台时不再让当前标题栏显示忙碌。
    await tester.pumpWidget(mount(visible: false));
    await tester.pump();
    expect(busy.busy, isFalse);

    await tester.pumpWidget(mount(visible: true));
    await tester.pump();
    expect(busy.busy, isTrue);

    await tester.pumpWidget(mount(visible: true, placeholder: false));
    await tester.pump();
    expect(busy.busy, isFalse);
  });

  test('外壳销毁后的迟到登记被忽略', () {
    final busy = UiBusyRegistry()..dispose();
    expect(() => busy.report(Object(), false), returnsNormally);
  });

  testWidgets('没有标题栏的面板内仍显示转圈', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoadingPlaceholder())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
