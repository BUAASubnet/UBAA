import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'backend.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    for (final scenario in [
      'normal',
      'cancel-error',
      'cancel-pending',
      'commit-pending',
      'commit-cross-deadline',
      'readback-pending',
      'unknown',
      'business-false',
      'exception',
      'expired',
    ]) {
      testWidgets('原生确认安全流程 $scenario ${brightness.name}', (tester) async {
        final backend = ConfirmationBackend(scenario);
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(
          UbaaFlutterApp(
            backend: backend,
            credentialVault: MemoryCredentialVault(),
            initialTab: 2,
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.widgetWithText(Card, FeatureId.signin.title));
        await tap(
          tester,
          find.ancestor(
            of: find.text('签到'),
            matching: find.byWidgetPredicate(
              (w) => w is FilledButton && w.onPressed != null,
            ),
          ),
        );
        expect(find.byType(WriteConfirmationView), findsOneWidget);
        expect(find.byType(Drawer), findsNothing);
        expect(find.byTooltip('刷新'), findsNothing);
        expect(find.text('实际路线'), findsNothing);
        expect(find.byTooltip('实际路线：直连'), findsOneWidget);
        expect(backend.commitCalls, 0);
        await shot(binding, tester, '$scenario-${brightness.name}-ready');
        if (scenario == 'normal') {
          await tap(tester, find.byTooltip('取消并返回'));
          expect(backend.cancelCalls, 1);
          expect(find.byType(WriteConfirmationView), findsNothing);
          await tap(
            tester,
            find.ancestor(
              of: find.text('签到'),
              matching: find.byWidgetPredicate(
                (w) => w is FilledButton && w.onPressed != null,
              ),
            ),
          );
        }
        if (scenario == 'expired') {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 3)),
          );
          await tester.pumpAndSettle();
          expect(find.text('意图已过期'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '意图已过期'),
                )
                .onPressed,
            isNull,
          );
          await shot(binding, tester, '$scenario-${brightness.name}-expired');
          await tap(tester, find.byTooltip('取消并返回'));
          expect(backend.commitCalls, 0);
          return;
        }
        if (scenario.startsWith('cancel-')) {
          if (scenario == 'cancel-pending') {
            backend.cancelGate = Completer<void>();
          }
          await tester.tap(find.byTooltip('取消并返回'));
          await tester.pump(const Duration(milliseconds: 300));
          if (scenario == 'cancel-pending') {
            await busy(tester);
            await shot(binding, tester, '$scenario-${brightness.name}-busy');
            backend.cancelGate!.complete();
          }
          await tester.pumpAndSettle();
          if (scenario == 'cancel-error') {
            expect(find.byType(WriteConfirmationView), findsOneWidget);
            expect(find.text('网络不可用'), findsOneWidget);
            await shot(binding, tester, '$scenario-${brightness.name}-error');
            await tap(tester, find.widgetWithText(OutlinedButton, '取消'));
            expect(backend.cancelCalls, 2);
          }
          expect(find.byType(WriteConfirmationView), findsNothing);
          expect(backend.commitCalls, 0);
          return;
        }
        if (scenario == 'commit-pending' ||
            scenario == 'commit-cross-deadline') {
          backend.commitGate = Completer<void>();
        }
        if (scenario == 'readback-pending') {
          backend.readbackGate = Completer<void>();
        }
        final reads = backend.academicReads
            .where((r) => r.$1 == FeatureId.signin)
            .length;
        await tester.tap(find.widgetWithText(FilledButton, '确认提交'));
        await tester.pump(const Duration(milliseconds: 300));
        if (scenario.endsWith('-pending') ||
            scenario == 'commit-cross-deadline') {
          if (scenario == 'commit-cross-deadline') {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 3)),
            );
            await tester.pump();
            expect(find.text('意图已过期'), findsNothing);
          }
          expect(backend.commitCalls, 1);
          await busy(tester);
          await shot(binding, tester, '$scenario-${brightness.name}-busy');
          backend.commitGate?.complete();
          backend.readbackGate?.complete();
        }
        await tester.pumpAndSettle();
        expect(backend.commitCalls, 1);
        expect(find.byType(WriteConfirmationView), findsNothing);
        final after = backend.academicReads
            .where((r) => r.$1 == FeatureId.signin)
            .length;
        if (scenario == 'unknown') {
          expect(find.text('提交结果不确定，请先刷新相关状态，不要重复提交。'), findsOneWidget);
          expect(after, reads + 1);
        } else if (scenario == 'business-false' || scenario == 'exception') {
          expect(after, reads);
          expect(find.text('合成签到完成'), findsNothing);
        } else {
          expect(after, reads + 1);
          expect(find.byTooltip('已签到'), findsOneWidget);
        }
        await shot(binding, tester, '$scenario-${brightness.name}-result');
      });
    }
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> busy(WidgetTester tester) async {
  expect(
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == '取消并返回',
          ),
        )
        .onPressed,
    isNull,
  );
  expect(
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
    isNull,
  );
  await tester.binding.handlePopRoute();
  await tester.pump();
  expect(find.byType(WriteConfirmationView), findsOneWidget);
}

Future<void> shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await tester.pump(const Duration(milliseconds: 250));
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize, ratio = tester.view.devicePixelRatio;
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add({
    'name': name,
    'backend': 'synthetic-write-confirmation',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'viewportSource': 'native-view-unmodified',
    'sourceSha': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
  });
  if (Platform.isIOS) await binding.takeScreenshot(name);
}
