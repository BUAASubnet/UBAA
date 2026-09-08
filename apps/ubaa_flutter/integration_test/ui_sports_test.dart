import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'ui_sports/backend.dart';
part 'ui_sports/support.dart';

final _photo = YgdkPhotoInput(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAO0lEQVR4nO3RQREAMAjEwKMW66K2MFoJ4cMvK+CYCXVfZ9NZXY8HBvwBMhEyETIRMhEyETIRMhEyUcgHOh4BoA8A/HAAAAAASUVORK5CYII=',
  ),
  fileName: 'synthetic-blue.png',
  mimeType: 'image/png',
);
Widget _app(SportsBackend backend) => UbaaFlutterApp(
  backend: backend,
  credentialVault: MemoryCredentialVault(),
  initialTab: 2,
  photoPicker: MemoryPhotoPicker(photo: _photo),
  permissionGateway: MemoryPermissionGateway(
    initial: {PlatformPermission.photos: PlatformPermissionStatus.granted},
  ),
);
void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      _app(
        SportsBackend(
          state: const String.fromEnvironment(
            'UBAA_UI_STATE',
            defaultValue: 'normal',
          ),
        ),
      ),
    );
    return;
  }
  WidgetController.hitTestWarningShouldBeFatal = true;
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('阳光原生旧首页查询详情与合成准备取消 ${brightness.name}', (tester) async {
      final backend = SportsBackend();
      await _mount(tester, backend, brightness, 'home');
      Future<void> shot(String scene, String steps) =>
          _shot(binding, tester, '${brightness.name}-normal-$scene', steps);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('合成运动项目 1'), findsNothing);
      await shot('home', '学期周次数后是记录；项目不铺首页');
      await _tap(tester, find.widgetWithText(Card, '合成运动记录 1'));
      await shot('record-detail', '低频编号及未知state进入只读详情，历史图片仅计数');
      await _tap(tester, find.text('关闭'));
      await _panel(tester);
      await _edit(tester, '筛选详情', '记录 2');
      await _closePanel(tester);
      expect(find.text('合成运动记录 1'), findsNothing);
      expect(find.text('合成运动记录 2'), findsOneWidget);
      await shot('filtered', '本地记录筛选关闭后保留，不重算学期次数');
      await _panel(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
            .controller!
            .text,
        '记录 2',
      );
      await _edit(tester, '筛选详情', '');
      await _closePanel(tester);
      await _panel(tester);
      await _edit(tester, '筛选详情', '999');
      await _closePanel(tester);
      expect(find.text('合成运动记录 3'), findsOneWidget);
      expect(find.text('合成运动记录 1'), findsNothing);
      await shot('metadata-filtered', '低频原始字段进入详情后仍可搜索');
      await _panel(tester);
      await _edit(tester, '筛选详情', '');
      await _closePanel(tester);
      await _tap(tester, find.byTooltip('新增打卡'));
      await shot('projects', '新增时才打开项目选择，无资格项目不可选');
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, '合成运动项目 3'))
            .enabled,
        isFalse,
      );
      await _tap(tester, find.text('合成运动项目 1'));
      await _tap(tester, find.text('继续确认'));
      expect(find.text('请填写完整时间并选择照片。'), findsOneWidget);
      expect(backend.prepared, isEmpty);
      await _edit(tester, '开始时间', '2026-09-09 08:00');
      await _edit(tester, '结束时间', '2026-09-09 09:00');
      await _edit(tester, '打卡地点', '合成操场');
      await _tap(tester, find.widgetWithText(OutlinedButton, '选择照片'));
      await shot('form', '显式合成纯色照片、时间和地点，保留当前校验');
      await _tap(tester, find.text('继续确认'));
      expect(backend.prepared.single.action.itemId, 7);
      expect(backend.prepared.single.shareToSquare, isFalse);
      await shot('confirm', '只进入合成prepare确认，未执行commit');
      await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
      expect(find.text('打卡记录'), findsOneWidget);
      await _panel(tester);
      await _tap(tester, find.byType(DropdownButton<FeatureQueryView>));
      await _tap(tester, find.text('记录列表').last);
      await _edit(tester, '页码', '2');
      await _edit(tester, '每页数量', '1');
      await shot('query', '全部原始分页查询在按需面板，草稿保留');
      await _tap(tester, find.text('应用筛选'));
      await _closePanel(tester);
      expect(backend.queries.last.page, 2);
      expect(backend.queries.last.size, 1);
      await shot('page2', '独立记录页一基分页与typed记录卡');
      await _tap(tester, find.byTooltip('上一页'));
      expect(backend.queries.last.page, 1);
      await shot('page1', '上一页恢复首批，未增加业务写入');
      expect(backend.commitCalls, 0);
    });
    if (const bool.fromEnvironment('UBAA_UI_NORMAL_ONLY')) continue;
    for (final view in ['home', 'records']) {
      for (final state in [
        'empty',
        'first-error',
        'partial-error',
        'stale',
        'loading',
        'long',
        'many',
      ]) {
        if (view == 'records' && state == 'partial-error') continue;
        testWidgets('阳光原生 $view $state ${brightness.name}', (tester) async {
          final backend = SportsBackend(state: state);
          if (state == 'long') {
            tester.platformDispatcher.textScaleFactorTestValue = 1.3;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
          }
          await _mount(tester, backend, brightness, view);
          Future<void> shot(String scene, String steps) => _shot(
            binding,
            tester,
            '${brightness.name}-$view-$state-$scene',
            steps,
          );
          if (state == 'stale') {
            backend.failNext = true;
            await _tap(tester, find.byTooltip('刷新当前查询'));
          } else if (state == 'loading') {
            final gate = Completer<void>();
            backend.pending = gate;
            await tester.tap(find.byTooltip('刷新当前查询'));
            await tester.pump(const Duration(milliseconds: 200));
            await shot('pending', '原生加载状态，旧内容不授予新写入');
            gate.complete();
            await tester.pumpAndSettle();
          } else if (state == 'many') {
            await shot('top', '42条合成记录首屏');
            if (view == 'home') {
              for (var page = 0; page < 2; page++) {
                await _tap(tester, find.text('加载更多'));
              }
            } else {
              await _panel(tester);
              await _edit(tester, '每页数量', '50');
              await _tap(tester, find.text('应用筛选'));
              await _closePanel(tester);
            }
            await _ensure(tester, find.text('合成运动记录 42'));
          }
          await shot('result', '明确合成状态，检查原生异常和页面内容');
          if (state == 'first-error') {
            await _tap(tester, find.widgetWithText(TextButton, '重试'));
            await shot('retry', '原生显式重试恢复同一读取视图');
          }
          if (state == 'long') {
            await _tap(
              tester,
              find
                  .ancestor(
                    of: find.byWidgetPredicate(
                      (w) => w is Text && (w.data ?? '').startsWith('合成运动记录 1'),
                    ),
                    matching: find.byType(Card),
                  )
                  .first,
            );
            await shot('detail', '1.3长文记录完整详情可以滚动');
            await _tap(tester, find.text('关闭'));
          }
          expect(backend.commitCalls, 0);
        });
      }
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  SportsBackend backend,
  Brightness brightness,
  String view,
) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(_app(backend));
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.ygdk.title));
  if (view == 'records') {
    await _panel(tester);
    await _tap(tester, find.byType(DropdownButton<FeatureQueryView>));
    await _tap(tester, find.text('记录列表').last);
    await _tap(tester, find.text('应用筛选'));
    await _closePanel(tester);
  }
}
