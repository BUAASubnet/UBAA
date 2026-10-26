import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../../integration_test/synthetic/bykc/feedback_backend.dart';

void main() {
  testWidgets('第二页选课后更新已加载页并保留原卡片位置', (tester) async {
    final backend = BoyaFeedbackBackend(state: 'many');
    await _open(tester, backend);
    final list = find.byType(ListView).last;
    final scrollFinder = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    final card = find.widgetWithText(Card, '合成课程 22');
    await tester.scrollUntilVisible(
      card,
      350,
      scrollable: scrollFinder,
      maxScrolls: 60,
    );
    final button = find.descendant(
      of: card,
      matching: find.widgetWithText(OutlinedButton, '选课'),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(scrollFinder);
    final offset = scroll.position.pixels;
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(card, findsOneWidget);
    backend.readback.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.position.pixels, closeTo(offset, 1));
    backend.refresh.complete();
    await tester.pumpAndSettle();
    expect(backend.refreshedPages, [1, 2]);
    expect(scroll.mounted, isTrue);
    expect(scroll.position.pixels, closeTo(offset, 1));
    expect(
      find.descendant(
        of: card,
        matching: find.widgetWithText(OutlinedButton, '退选'),
      ),
      findsOneWidget,
    );
    expect(backend.commitCalls, 1);
  });
  for (final failRefresh in [false, true]) {
    testWidgets('选课回读和刷新${failRefresh ? '失败' : '成功'}期间保留列表与位置', (tester) async {
      final backend = BoyaFeedbackBackend()..failRefresh = failRefresh;
      await _open(tester, backend);
      final card = find.widgetWithText(Card, '合成课程 1');
      final button = find.descendant(
        of: card,
        matching: find.widgetWithText(OutlinedButton, '选课'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.ancestor(of: card, matching: find.byType(Scrollable)).first,
      );
      scroll.position.jumpTo(60);
      await tester.pumpAndSettle();
      final offset = scroll.position.pixels;
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.commitCalls, 1);
      expect(backend.cachedCommits, 1);
      expect(backend.readbacks, 1);
      expect(card, findsOneWidget);
      expect(scroll.mounted, isTrue);
      expect(scroll.position.pixels, closeTo(offset, 1));
      expect(find.byType(FriendlyErrorCard), findsNothing);

      backend.readback.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.refreshes, 1);
      expect(card, findsOneWidget);
      expect(scroll.mounted, isTrue);
      expect(scroll.position.pixels, closeTo(offset, 1));
      expect(find.byType(FriendlyErrorCard), findsNothing);
      backend.refresh.complete();
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(scroll.mounted, isTrue);
      expect(scroll.position.pixels, closeTo(offset, 1));
      expect(backend.commitCalls, 1);
      if (failRefresh) {
        expect(find.byType(MaterialBanner), findsOneWidget);
        expect(
          tester
              .widgetList<OutlinedButton>(
                find.descendant(
                  of: card,
                  matching: find.byType(OutlinedButton),
                ),
              )
              .every((button) => button.onPressed == null),
          isTrue,
        );
        backend.failRefresh = false;
        await _tap(tester, find.widgetWithText(TextButton, '重试'));
      }
      expect(
        find.descendant(
          of: card,
          matching: find.widgetWithText(OutlinedButton, '退选'),
        ),
        findsOneWidget,
      );
      expect(backend.commitCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _open(WidgetTester tester, BoyaFeedbackBackend backend) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final materials = SecureMaterialStore(transport: _MemoryMaterials());
  await materials.probe();
  final accounts = SecureLocalAccountStore(materials);
  await accounts.retain('coursework-fixture', retainSession: true);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      localAccountStore: accounts,
      initialDestination: UiDestination.coursework,
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.bykc.title));
  await _tap(tester, find.widgetWithText(Card, '选择课程'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _MemoryMaterials implements SecureMaterialTransport {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
