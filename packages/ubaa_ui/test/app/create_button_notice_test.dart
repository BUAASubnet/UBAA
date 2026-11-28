import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import '../agenda/support.dart';
import '../support/home_shell_harness.dart';

void main() {
  testWidgets('外壳提示避开日程创建按钮，切到首页后恢复底栏间距', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    const username = 'synthetic';
    final service = AgendaService(MemoryAgenda());
    await service.openAccount(username);
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: HomeShellHarness(
          child: UbaaMainShell(
            user: const UserSummary(username: username),
            initialDestination: UiDestination.agenda,
            agenda: AgendaAccess(service: service, term: ''),
            snapshots: const {},
            routePolicy: RoutePolicy.auto,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navigationBar = find.byType(NavigationBar);
    final shellScaffold = find.ancestor(
      of: navigationBar,
      matching: find.byType(Scaffold),
    );
    final createButton = find.byType(FloatingActionButton);
    final button = tester.widget<FloatingActionButton>(createButton);
    expect(button.tooltip, '新建事项');
    expect(button.onPressed, isNotNull);
    expect(createButton.hitTestable(), findsOneWidget);

    const message = '操作成功';
    UbaaFeedback.show(
      tester.element(createButton),
      message,
      kind: UbaaFeedbackKind.success,
    );
    await tester.pumpAndSettle();

    final feedbackCard = find
        .descendant(
          of: find.byType(SnackBar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Material && widget.shape is RoundedRectangleBorder,
          ),
        )
        .first;
    expect(find.text(message), findsOneWidget);
    final cardRect = tester.getRect(feedbackCard);
    final buttonRect = tester.getRect(createButton);
    expect(cardRect.overlaps(buttonRect), isFalse);
    expect(cardRect.bottom, lessThanOrEqualTo(buttonRect.top));
    expect(createButton.hitTestable(), findsOneWidget);
    expect(
      tester.widget<Scaffold>(shellScaffold).floatingActionButton,
      isNotNull,
    );

    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.home.index),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(navigationBar).selectedIndex,
      UiDestination.home.index,
    );
    expect(createButton.hitTestable(), findsNothing);
    expect(find.text(message), findsOneWidget);
    expect(tester.widget<Scaffold>(shellScaffold).floatingActionButton, isNull);
    // 外壳底栏在 NavigationBar 上方留有间隙，默认间距以整条底栏的外缘为准。
    final bottomBar = tester
        .widget<Scaffold>(shellScaffold)
        .bottomNavigationBar!;
    final barTop = tester.getTopLeft(find.byWidget(bottomBar)).dy;
    expect(tester.getRect(feedbackCard).bottom, closeTo(barTop - 10, 0.5));
  });
}
