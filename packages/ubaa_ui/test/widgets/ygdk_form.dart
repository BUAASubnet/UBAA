part of '../widgets_test.dart';

void _registerYgdkFormTests() {
  Future<void> mount(
    WidgetTester tester,
    YgdkPhotoPicker picker, {
    YgdkPhotoPicker? camera,
  }) async {
    await _pumpYgdkShell(
      tester,
      key: const ValueKey('阳光表单'),
      prepare: (_) async => throw StateError('不应准备'),
      picker: picker,
      camera: camera,
      commit: (_) async => throw StateError('不应提交'),
      discard: (_) async {},
      refresh: ({required expectedRoute}) async {},
    );
  }

  testWidgets('阳光独立表单返回保留文字草稿但释放照片', (tester) async {
    await mount(tester, _validYgdkPhoto);
    await _openAndFillYgdkForm(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.widgetWithText(AppBar, '填写阳光打卡信息'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备阳光打卡'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '开始时间'))
          .controller!
          .text,
      '2026-09-01 08:00',
    );
    expect(find.byKey(const ValueKey('ygdk-photo-preview')), findsNothing);
  });

  testWidgets('阳光取消更换照片保留先前照片', (tester) async {
    var calls = 0;
    await mount(
      tester,
      () async => ++calls == 1 ? await _validYgdkPhoto() : null,
    );
    await _openAndFillYgdkForm(tester);
    final replace = find.text('已选择照片：photo.png');
    await tester.ensureVisible(replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const ValueKey('ygdk-photo-preview')), findsOneWidget);
    expect(find.text('已选择照片：photo.png'), findsOneWidget);
  });

  testWidgets('阳光更换照片失败保留原图并明确大小和访问限制', (tester) async {
    var calls = 0;
    await mount(tester, () async {
      if (++calls == 1) return _validYgdkPhoto();
      throw StateError('合成原始路径不能显示');
    });
    await _openAndFillYgdkForm(tester);
    final replace = find.text('已选择照片：photo.png');
    await tester.ensureVisible(replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ygdk-photo-preview')), findsOneWidget);
    expect(find.text('已选择照片：photo.png'), findsOneWidget);
    expect(find.text('无法读取照片，请使用不超过10 MiB的图片，并检查系统访问权限。'), findsOneWidget);
    expect(find.textContaining('合成原始路径不能显示'), findsNothing);
  });

  testWidgets('阳光拍照与选图共享等待并在取消后保留原图', (tester) async {
    final pending = Completer<YgdkPhotoInput?>();
    var calls = 0;
    await mount(
      tester,
      _validYgdkPhoto,
      camera: () {
        calls++;
        return pending.future;
      },
    );
    await _openAndFillYgdkForm(tester);
    final camera = find.widgetWithText(OutlinedButton, '拍摄照片');
    await tester.ensureVisible(camera);
    await tester.tap(camera);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(camera).onPressed, isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '已选择照片：photo.png'),
          )
          .onPressed,
      isNull,
    );
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('已选择照片：photo.png'), findsOneWidget);
    expect(find.byKey(const ValueKey('ygdk-photo-preview')), findsOneWidget);
    expect(tester.widget<OutlinedButton>(camera).onPressed, isNotNull);
  });

  testWidgets('阳光拍照成功替换预览且退出后迟到拍照不恢复', (tester) async {
    final pending = Completer<YgdkPhotoInput?>();
    var calls = 0;
    await mount(
      tester,
      _validYgdkPhoto,
      camera: () async {
        if (++calls > 1) return pending.future;
        final photo = await _validYgdkPhoto();
        return YgdkPhotoInput(
          bytes: photo.bytes,
          fileName: 'camera.png',
          mimeType: photo.mimeType,
        );
      },
    );
    await _openAndFillYgdkForm(tester);
    final camera = find.text('拍摄照片');
    await tester.ensureVisible(camera);
    await tester.tap(camera);
    await tester.pumpAndSettle();
    expect(find.text('已选择照片：camera.png'), findsOneWidget);
    await tester.tap(camera);
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    pending.complete(await _validYgdkPhoto());
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备阳光打卡'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ygdk-photo-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('阳光时间选择双确认后回填且取消不覆盖草稿', (tester) async {
    await mount(tester, _validYgdkPhoto);
    await _openAndFillYgdkForm(tester);
    final choose = find.byTooltip('选择开始时间');
    await tester.ensureVisible(choose);
    await tester.pumpAndSettle();
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, '开始时间');
    expect(
      tester.widget<TextField>(field).controller!.text,
      '2026-09-01 08:00',
    );
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定时间'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field).controller!.text,
      '2026-09-02 08:00',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('阳光退出表单后迟到照片不能恢复到新表单', (tester) async {
    final pending = Completer<YgdkPhotoInput?>();
    await mount(tester, () => pending.future);
    await _openYgdkDetails(tester);
    await tester.tap(find.text('准备阳光打卡'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('选择照片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择照片'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '继续确认'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备阳光打卡'));
    await tester.pumpAndSettle();
    pending.complete(await _validYgdkPhoto());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ygdk-photo-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('阳光宿主失效关闭表单和时间选择器', (tester) async {
    await mount(tester, _validYgdkPhoto);
    await _openAndFillYgdkForm(tester);
    await tester.ensureVisible(find.byTooltip('选择开始时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择开始时间'));
    await tester.pumpAndSettle();
    await _pumpYgdkShell(tester, key: const ValueKey('新账号'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('填写阳光打卡信息'), findsNothing);
    expect(find.byKey(const ValueKey('ygdk-photo-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
