import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'backend.dart';
part 'support.dart';

void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: AcademicOldBackend(),
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    for (final feature in [FeatureId.exam, FeatureId.signin]) {
      if (const String.fromEnvironment('UBAA_UI_FEATURE') == 'exam' &&
          feature != FeatureId.exam) {
        continue;
      }
      testWidgets('旧版原生 ${feature.name} 正常 ${brightness.name}', (tester) async {
        final backend = AcademicOldBackend();
        await mount(tester, backend, brightness, feature);
        Future<void> shot(String name, String steps) => capture(
          binding,
          tester,
          '${brightness.name}-${feature.name}-$name',
          steps,
        );
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        await shot('list', '沿旧列表结构，查询入口只有顶栏，手机功能页无全局底栏');
        final count = backend.academicReads.length;
        await tap(tester, find.byTooltip('搜索与筛选'));
        await tap(tester, find.widgetWithText(TextField, '筛选详情'));
        await tester.enterText(
          find.widgetWithText(TextField, '筛选详情'),
          feature == FeatureId.exam ? '待考' : '可签到',
        );
        await closePanel(tester);
        await shot('filtered', '按需筛选关闭后保持结果，无额外请求');
        await tap(tester, find.byTooltip('搜索与筛选'));
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
              .controller!
              .text,
          feature == FeatureId.exam ? '待考' : '可签到',
        );
        await tap(tester, find.widgetWithText(TextField, '筛选详情'));
        await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
              .controller!
              .text,
          '',
        );
        await closePanel(tester);
        expect(backend.academicReads.length, count);
        if (feature == FeatureId.exam) {
          expect(find.text('合成已结束考试 1'), findsNothing);
          await tap(tester, find.text('已结束考试 (2)'));
          await shot('finished', '已结束展开按日期倒序，未来升序，待定与未安排保留');
          await tap(tester, find.text('已结束考试 (2)'));
          await tap(tester, find.text('合成待考课程'));
          await shot('detail', '本地完整日期时间地点座位，不请求网络');
          await tap(tester, find.text('更多信息'));
          await shot('detail-more', '任务编号与课程编号仅在本地详情');
          await tap(tester, find.widgetWithText(TextButton, '关闭'));
        } else {
          await tap(tester, find.widgetWithText(FilledButton, '签到').first);
          expect(backend.preparedSignin, ['target-可签到']);
          await shot('prepare', '原始typed目标进入协调器，明确合成prepare');
          await tap(tester, find.widgetWithText(OutlinedButton, '取消'));
          expect(backend.commitCalls, 0);
          await tap(tester, find.text('合成已签到课程'));
          await shot('detail', '已签到说明、原状态与低频字段按需查看');
          await tap(tester, find.widgetWithText(TextButton, '关闭'));
          await ensure(tester, find.text('未提供签到目标，请刷新课程后重试。'));
          await shot('eligibility', '未知资格与缺少目标明确说明，不伪造动作');
        }
        expect(backend.commitCalls, 0);
      });
      for (final state in [
        'empty',
        'first-error',
        'stale',
        'loading',
        'long',
        'many',
      ]) {
        if (state == 'many' && feature == FeatureId.signin) continue;
        testWidgets('旧版原生 ${feature.name} $state ${brightness.name}', (
          tester,
        ) async {
          final backend = AcademicOldBackend(state: state);
          if (state == 'long') {
            tester.platformDispatcher.textScaleFactorTestValue = 1.3;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
          }
          await mount(tester, backend, brightness, feature);
          Future<void> shot(String name) => capture(
            binding,
            tester,
            '${brightness.name}-${feature.name}-$state-$name',
            '显式合成状态，原生视口与真实字体',
          );
          if (state == 'stale' || state == 'loading') {
            if (state == 'stale') backend.failFeatures.add(feature);
            if (state == 'loading') backend.pending = Completer<void>();
            final reads = backend.academicReads.length;
            await tester.tap(find.byTooltip('刷新当前查询'));
            await tester.pump(const Duration(milliseconds: 300));
            expect(backend.academicReads.length, greaterThan(reads));
            if (state == 'loading') {
              expect(find.byType(CircularProgressIndicator), findsWidgets);
            }
            await shot('refresh');
            backend.pending?.complete();
            await tester.pumpAndSettle();
            if (state == 'stale') {
              expect(find.text('以下为上次成功加载的数据。'), findsOneWidget);
            }
          }
          await shot('top');
          if (state == 'first-error') {
            await tap(tester, find.text('重试'));
            await shot('retry');
          } else if (state == 'many') {
            expect(find.text('合成待考课程'), findsOneWidget);
            await tap(tester, find.text('已结束考试 (42)'));
            await ensure(tester, find.text('合成已结束考试 42'));
            await shot('finished-bottom');
          } else if (state == 'long') {
            await tap(
              tester,
              find.text(
                backend.title(feature == FeatureId.exam ? '合成待考课程' : '合成已签到课程'),
              ),
            );
            await shot('detail');
            await tap(tester, find.widgetWithText(TextButton, '关闭'));
          }
        });
      }
    }
  }
}

Future<void> mount(
  WidgetTester tester,
  AcademicOldBackend backend,
  Brightness brightness,
  FeatureId feature,
) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialTab: ordinaryFeatureIds.contains(feature) ? 1 : 2,
    ),
  );
  await tester.pumpAndSettle();
  final card = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.widgetWithText(Card, feature.title),
  );
  await tap(tester, card);
}

Future<void> closePanel(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tap(tester, find.widgetWithText(TextButton, '完成'));
}
