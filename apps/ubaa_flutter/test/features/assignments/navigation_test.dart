import 'package:ubaa_ui/src/features/coursework/assignment_content.dart'
    show AssignmentCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../../integration_test/synthetic/assignments/backend.dart';

void main() {
  testWidgets('真实App控制器单项返回后换搜索保留其他父作业', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> ensure(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          240,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .last,
          maxScrolls: 60,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder finder) async {
      await ensure(finder);
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    final searchField = find.byKey(
      const ValueKey<String>('feature-search-field'),
    );

    Future<void> panel() async {
      if (find.byTooltip('关闭筛选').hitTestable().evaluate().isEmpty) {
        await tap(find.byKey(const ValueKey<String>('feature-filter-button')));
      }
    }

    Future<void> closePanel() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(find.byTooltip('关闭筛选'));
    }

    Future<void> search(String value) async {
      await ensure(searchField);
      await tester.enterText(searchField, value);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: CourseworkBackend(),
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'synthetic-coursework',
    );
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    FocusManager.instance.primaryFocus?.unfocus();
    await tap(find.widgetWithText(FilledButton, '登录'));
    await tap(find.widgetWithText(NavigationDestination, '课程与作业'));
    await tap(find.widgetWithText(Card, FeatureId.judge.title));
    await panel();
    await tap(find.text('显示已截止'));
    await closePanel();
    await search('judge-a');
    await tap(find.byType(AssignmentCard));
    await tap(find.byTooltip('返回'));
    await search('judge-b');
    expect(tester.widget<TextField>(searchField).controller!.text, 'judge-b');
    await tap(find.byType(AssignmentCard));
    expect(find.textContaining('judge-b'), findsWidgets);
  });
}
