import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'coursework_content_test.dart' as coursework;

void main() {
  testWidgets('从列表底部翻下一页回到新页顶部并保留批量选择', (tester) async {
    await coursework.showFeature(tester, FeatureId.judge, [
      for (var i = 0; i < 42; i++) coursework.judge('$i'),
    ], []);
    final last = find.byKey(const ValueKey(('judge-selection', '19', 'same')));
    final list = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last;
    await tester.scrollUntilVisible(
      last,
      500,
      scrollable: list,
      maxScrolls: 40,
    );
    await Scrollable.ensureVisible(tester.element(last), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(last.hitTestable(), findsOneWidget);
    await tester.tap(last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('已选择 1 份作业'), findsOneWidget);
    expect(find.text('20 作业').hitTestable(), findsOneWidget);
  });
}
