part of 'flow_test.dart';

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
      await _tap(tester, find.byKey(const ValueKey('libbook-choice-时段')));
      await _tap(tester, find.text('下午 14:00–16:00').last);
      expect(backend.libraryReads, hasLength(count + 1));
      expect(backend.libraryReads.last.segment, 'segment-b');
      expect(backend.libraryReads.last.startTime, '14:00');
      expect(backend.libraryReads.last.endTime, '16:00');
      await shot('seats', '切换同日时段后自动查询座位，地图入口仍对应实际areaId');
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
      await _chooseLibraryOption(tester, '分区', '安静阅览区 2 · 合成校区 · 空闲 1/10');
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
