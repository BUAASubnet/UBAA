part of '../ui_library_test.dart';

void registerLibraryMapTests(IntegrationTestWidgetsFlutterBinding binding) {
  test('图书馆29张地图在原生包内完整可读', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final maps = manifest
        .listAssets()
        .where(
          (name) =>
              name.startsWith('packages/ubaa_ui/assets/libbook_maps/') &&
              name.endsWith('.png'),
        )
        .toList();
    expect(maps, hasLength(29));
    for (final map in maps) {
      final data = await rootBundle.load(map);
      expect(data.lengthInBytes, greaterThan(100));
      expect(data.getUint8(0), 137);
      expect(data.getUint8(1), 80);
    }
  });
  for (final brightness in Brightness.values) {
    testWidgets('图书馆原生地图和时段草稿 ${brightness.name}', (tester) async {
      final backend = LibraryBackend(state: 'map');
      await _mount(tester, backend, brightness);
      expect(backend.libraryReads.last.areaId, '8');
      final count = backend.libraryReads.length;
      Future<void> shot(String scene, String steps) =>
          _shot(binding, tester, '${brightness.name}-map-$scene', steps);
      await _tap(tester, find.text('查看座位分布'));
      final viewer = find.byType(InteractiveViewer);
      expect(viewer, findsOneWidget);
      final controller = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      expect(controller.value.getMaxScaleOnAxis(), 1);
      await shot('fit', '打开冻结分区8静态分布，颜色与可用性说明可见');
      await _tap(tester, find.byTooltip('放大'));
      expect(controller.value.getMaxScaleOnAxis(), 2);
      await shot('zoom', '实际点击放大，查看座位标号');
      final beforePan = controller.value.getTranslation();
      await tester.drag(viewer, const Offset(80, 60));
      await tester.pumpAndSettle();
      expect(controller.value.getTranslation(), isNot(beforePan));
      await shot('pan', '放大后实际拖动平面图');
      await _tap(tester, find.text('重置'));
      expect(controller.value.getMaxScaleOnAxis(), 1);
      expect(controller.value.getTranslation().x, 0);
      await _tap(tester, find.byTooltip('关闭'));
      expect(backend.libraryReads, hasLength(count));
      await _tap(tester, find.widgetWithText(ActionChip, '下午 14:00–16:00'));
      expect(backend.libraryReads, hasLength(count));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '日期'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '开始时间'))
            .controller!
            .text,
        '14:00',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '结束时间'))
            .controller!
            .text,
        '16:00',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '时段编号（必填）'))
            .controller!
            .text,
        'segment-b',
      );
      await shot('draft', '时段一次回填原始ID与起止，未自动赋予日期');
      await _edit(tester, '日期', '2026-09-04');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
      await _closePanel(tester);
      expect(backend.libraryReads, hasLength(count + 1));
      expect(backend.libraryReads.last.segment, 'segment-b');
      expect(backend.libraryReads.last.startTime, '14:00');
      expect(backend.libraryReads.last.endTime, '16:00');
      await shot('seats', '明确填写日期后查询座位，地图入口仍对应实际areaId');
      await _tap(tester, find.text('查看座位分布'));
      expect(
        tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        1,
      );
      await _tap(tester, find.byTooltip('关闭'));
      await _tap(tester, find.widgetWithText(Card, '安静阅览区 2'));
      expect(find.text('当前分区暂无平面图'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '查看座位分布'),
            )
            .onPressed,
        isNull,
      );
      await shot('unknown', '切换到未打包分区后不借用上一张地图');
      expect(backend.commitCalls, 0);
    });
  }
}
