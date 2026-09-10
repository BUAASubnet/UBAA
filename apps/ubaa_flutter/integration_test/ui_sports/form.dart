part of '../ui_sports_test.dart';

void _registerSportsForm(IntegrationTestWidgetsFlutterBinding binding) {
  for (final brightness in Brightness.values) {
    for (final scenario in [
      'success',
      'unknown',
      'readback-failure',
      'upload-failure',
      'cancel-failure',
      'expired',
      'pending',
    ]) {
      testWidgets('阳光原生完整内存写入 $scenario ${brightness.name}', (tester) async {
        final backend = SportsWriteBackend(scenario);
        await _mount(tester, backend, brightness, 'home');
        Future<void> shot(String scene, String steps) => _shot(
          binding,
          tester,
          '${brightness.name}-write-$scenario-$scene',
          steps,
        );
        await _tap(tester, find.byTooltip('新增打卡'));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byTooltip('实际路线：直连'), findsOneWidget);
        await shot('empty', '旧独立表单的项目时间地点照片分享顺序；正文不铺实现ID');
        await _tap(tester, find.text('选择运动项目'));
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, '合成运动项目 3'))
              .enabled,
          isFalse,
        );
        await _tap(tester, find.text('合成运动项目 1'));
        await _edit(tester, '开始时间', '2026-09-09 08:00');
        await _edit(tester, '结束时间', '2026-09-09 09:00');
        await _edit(tester, '打卡地点', '合成操场');
        if (scenario == 'success') {
          await _tap(tester, find.byTooltip('选择开始时间'));
          await shot('date', '系统中文日期选择；取消不覆盖草稿');
          await _tap(tester, find.text('下一步'));
          await shot('time', '原生中文24小时选择；双确认才回填');
          await _tap(tester, find.text('确定时间'));
          await _tap(tester, find.text('取消'));
          await _tap(tester, find.byTooltip('新增打卡'));
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, '开始时间'))
                .controller!
                .text,
            '2026-09-09 08:00',
          );
          expect(find.text('合成运动项目 1'), findsOneWidget);
        }
        await _tap(tester, find.text('选择照片'));
        if (scenario == 'success') {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await _tap(tester, find.text('分享到打卡广场'));
          expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isTrue,
          );
          await shot('share', '单行分享标题与默认说明，显式开关不会自动提交');
          await _tap(tester, find.text('分享到打卡广场'));
        }
        await shot('photo', '仅合成32像素纯色照片，预览不裁掉操作');
        if (scenario == 'success') {
          await _tap(tester, find.text('清除照片'));
          expect(
            find.byKey(const ValueKey('ygdk-photo-preview')),
            findsNothing,
          );
          await _tap(tester, find.text('选择照片'));
        }
        await _tap(tester, find.text('继续确认'));
        expect(backend.prepared.length, 1);
        expect(backend.prepared.single.action.itemId, 7);
        expect(backend.prepared.single.photo.fileName, 'synthetic-blue.png');
        await shot('confirm', '显式合成prepare，保留实际直连与期限保护');
        if (scenario == 'expired') {
          expect(backend.commitCalls, 0);
          expect(
            find.widgetWithText(FilledButton, '确认提交').hitTestable(),
            findsNothing,
          );
          return;
        }
        if (scenario == 'cancel-failure') {
          await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
          expect(backend.cancelFailed, isTrue);
          expect(backend.active.length, 1);
          await shot('cancel-error', '取消失败保留确认页，可重试，无commit');
          await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
          expect(backend.active, isEmpty);
          expect(backend.commitCalls, 0);
          await shot('cancelled', '取消重试成功返回原记录');
          return;
        }
        if (scenario == 'pending') {
          backend.commitGate = Completer<void>();
          await tester.tap(find.text('确认提交'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(backend.commitCalls, 1);
          expect(
            tester
                .widget<FilledButton>(find.byType(FilledButton).last)
                .onPressed,
            isNull,
          );
          await shot('pending', '合成commit在途，确认与返回不可重复触发');
          backend.commitGate!.complete();
          await tester.pumpAndSettle();
        } else {
          await _tap(tester, find.text('确认提交'));
        }
        expect(backend.commitCalls, 1);
        expect(backend.active, isEmpty);
        if (scenario == 'unknown') {
          expect(find.textContaining('结果不确定'), findsWidgets);
          expect(find.textContaining('已核对'), findsNothing);
        } else if (scenario == 'upload-failure') {
          expect(find.textContaining('未执行最终提交'), findsOneWidget);
          expect(backend.committed, isFalse);
        } else {
          expect(find.textContaining('合成打卡已提交'), findsOneWidget);
        }
        if (scenario != 'upload-failure') {
          expect(backend.pinnedReads, [
            'overview:direct',
            'records:direct:1:20',
          ]);
        }
        await shot('result', '合成结果与原路线回读；失败与未知不冒称已核对');
        if (backend.committed && scenario != 'readback-failure') {
          expect(find.text('合成新增运动记录'), findsOneWidget);
        }
        await shot('readback', '返回阳光首页检查最新记录或准确失败状态');
      });
    }
  }
}
