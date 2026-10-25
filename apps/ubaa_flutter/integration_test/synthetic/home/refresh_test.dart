import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../libbook/backend.dart';

/// 使用设备原始视口和触摸拖动；所有查询均为合成回调。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final status in [
    FeatureLoadStatus.success,
    FeatureLoadStatus.empty,
    FeatureLoadStatus.failure,
  ]) {
    testWidgets('原生所有功能页 ${status.name} 下拉刷新', (tester) async {
      for (final feature in FeatureId.values) {
        final reads = <FeatureId>[];
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: UbaaMainShell(
              initialDestination: UiDestination.forFeature(feature),
              user: const UserSummary(username: 'synthetic-refresh'),
              snapshots: {
                for (final id in FeatureId.values)
                  id: FeatureSnapshot(
                    feature: id,
                    status: id == feature ? status : FeatureLoadStatus.empty,
                    details:
                        id == feature && status == FeatureLoadStatus.success
                        ? const [FeatureDetail(title: '合成短列表')]
                        : const [],
                    error: id == feature && status == FeatureLoadStatus.failure
                        ? const UiError(
                            code: UbaaErrorCode.networkError,
                            title: '加载失败',
                            message: '合成失败',
                            retryable: true,
                          )
                        : null,
                  ),
              },
              routePolicy: RoutePolicy.auto,
              telemetryEnabled: false,
              onRefresh: () async {},
              onRetryFeature: (id) async {
                reads.add(id);
              },
              onLogout: () async {},
              onLogoutAndClearAccount: () async {},
              onRoutePolicyChanged: (_) {},
              onTelemetryChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openCard(tester, feature.title);
        await pull(tester);
        expect(reads, [feature], reason: '${feature.name}/${status.name}');
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('原生图书馆下拉重读顶部汇总并合并按钮重复刷新', (tester) async {
    final backend = LibraryBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        key: UniqueKey(),
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialDestination: UiDestination.campus,
      ),
    );
    await tester.pumpAndSettle();
    await openCard(tester, FeatureId.libbook.title);
    await openCard(tester, '预约座位');
    final before = backend.libraryReads.length;
    final gate = Completer<void>();
    backend.pending = gate;
    await pull(tester, settle: false);
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pump();
    expect(backend.libraryReads, hasLength(before + 1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(backend.libraryReads.skip(before).map((q) => q.view), [
      FeatureQueryView.summary,
      FeatureQueryView.libbookAreas,
      FeatureQueryView.libbookAreaDetail,
      FeatureQueryView.libbookSeats,
    ]);
    expect(backend.commitCalls, 0);
  });
}

Future<void> openCard(WidgetTester tester, String title) async {
  final card = find.widgetWithText(Card, title);
  if (card.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .last,
    );
  }
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Future<void> pull(WidgetTester tester, {bool settle = true}) async {
  final scroll = find
      .descendant(
        of: find.byType(RefreshIndicator).last,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final rect = tester.getRect(scroll);
  await tester.dragFrom(rect.center, const Offset(0, 320));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(seconds: 1));
  }
}
