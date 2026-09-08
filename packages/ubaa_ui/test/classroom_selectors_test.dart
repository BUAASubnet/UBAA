import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support/navigation.dart';

void main() {
  testWidgets('楼层选择只回填typed ID，应用不发送展示假值', (tester) async {
    final h = await _open(tester);
    await _pick(tester, '选择楼层', '二层 · F02');
    expect(_text(tester, '楼层'), 'F02');
    expect(h.queries, isEmpty);
    await _apply(tester);
    expect(h.queries.single.floorId, 'F02');
    expect(h.queries.single.date, DateTime(2026, 9, 8));
    expect(h.queries.single.campus, 1);
  });
  testWidgets('筛选子集后仍能选择之前同日期校区的另一楼层', (tester) async {
    final h = await _open(tester);
    await _pick(tester, '选择楼层', '二层 · F02');
    h.snapshot = _snapshot(3, floors: const ['F02'], floor: 'F02');
    h.notifyListeners();
    await tester.pumpAndSettle();
    await _pick(tester, '选择楼层', '三层 · F03');
    await _apply(tester);
    expect(h.queries.single.floorId, 'F03');
  });
  testWidgets('切换日期期间抵达的旧日期结果不能在切回后复活', (tester) async {
    final h = await _open(tester);
    await tester.enterText(find.widgetWithText(TextField, '日期'), '2026-09-09');
    h.snapshot = _snapshot(3);
    h.notifyListeners();
    await tester.pumpAndSettle();
    await openQueryPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, '日期'), '2026-09-08');
    h.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择楼层'));
    await tester.pumpAndSettle();
    expect(find.text('二层 · F02'), findsNothing);
    expect(find.textContaining('先查询该日期校区'), findsOneWidget);
  });
  testWidgets('选择对话框打开后epoch变化不能填回旧楼层', (tester) async {
    final h = await _open(tester);
    await tester.tap(find.byTooltip('选择楼层'));
    await tester.pumpAndSettle();
    h.epoch++;
    h.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.text('二层 · F02'));
    await tester.pumpAndSettle();
    expect(_text(tester, '楼层'), isEmpty);
    expect(h.queries, isEmpty);
  });
  testWidgets('epoch同时到达新读取loading不提前消费随后success', (tester) async {
    final h = await _open(tester);
    final result = _snapshot(3, floors: const ['F03']);
    h.epoch++;
    h.snapshot = result.copyWith(status: FeatureLoadStatus.loading);
    h.notifyListeners();
    await tester.pump();
    h.snapshot = result;
    h.notifyListeners();
    await tester.pumpAndSettle();
    await _pick(tester, '选择楼层', '三层 · F03');
    expect(_text(tester, '楼层'), 'F03');
    expect(h.queries, isEmpty);
  });
  for (final kind in ['日期', '校区', 'epoch']) {
    testWidgets('$kind变化后同旧snapshot重绘不能复活选项', (tester) async {
      final h = await _open(tester);
      if (kind == '日期') {
        await tester.enterText(
          find.widgetWithText(TextField, '日期'),
          '2026-09-09',
        );
        await tester.enterText(
          find.widgetWithText(TextField, '日期'),
          '2026-09-08',
        );
      } else if (kind == '校区') {
        await _campus(tester, '校区 2');
        await _campus(tester, '校区 1');
      } else {
        h.epoch++;
      }
      h.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('选择楼层'));
      await tester.pumpAndSettle();
      expect(find.text('二层 · F02'), findsNothing);
      expect(find.textContaining('先查询该日期校区'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      h.snapshot = _snapshot(3);
      h.notifyListeners();
      await tester.pumpAndSettle();
      await _pick(tester, '选择楼层', '三层 · F03');
      expect(_text(tester, '楼层'), 'F03');
    });
  }
  testWidgets('节次仅完整正整数令牌，选择3和13保持精确query', (tester) async {
    final h = await _open(tester);
    await tester.tap(find.byTooltip('选择节次'));
    await tester.pumpAndSettle();
    expect(find.text('第 0 节'), findsNothing);
    expect(find.text('第 -1 节'), findsNothing);
    expect(find.text('第 3-4 节'), findsNothing);
    await tester.tap(find.text('第 3 节'));
    await tester.pumpAndSettle();
    expect(h.queries, isEmpty);
    await _apply(tester);
    expect(h.queries.single.section, '3');
    await _pick(tester, '选择节次', '第 13 节');
    await _apply(tester);
    expect(h.queries.last.section, '13');
  });
  testWidgets('元数据缺失不猜来源，手填仍发送原参数', (tester) async {
    final h = await _open(tester, metadata: false);
    await tester.tap(find.byTooltip('选择楼层'));
    await tester.pumpAndSettle();
    expect(find.text('二层 · F02'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '楼层'),
      'manual-floor',
    );
    await tester.enterText(find.widgetWithText(TextField, '节次'), '13');
    await _apply(tester);
    expect(h.queries.single.floorId, 'manual-floor');
    expect(h.queries.single.section, '13');
  });
}

class _Harness extends ChangeNotifier {
  _Harness(this.snapshot);
  FeatureSnapshot snapshot;
  int epoch = 0;
  final queries = <FeatureQuery>[];
}

FeatureSnapshot _snapshot(
  int revision, {
  List<String> floors = const ['F02', 'F03'],
  String? floor,
  bool metadata = true,
}) => FeatureSnapshot(
  feature: FeatureId.classroom,
  status: FeatureLoadStatus.success,
  readContext: FeatureReadContext(
    requestRevision: revision,
    query: FeatureQuery(date: DateTime(2026, 9, 8), campus: 1, floorId: floor),
  ),
  details: [
    for (final id in floors)
      FeatureDetail(
        title: '教室 $id',
        fields: const [
          FeatureField(label: '楼层', value: '展示假值'),
          FeatureField(label: '节次', value: '999'),
        ],
        presentation: ClassroomPresentation(
          roomId: id,
          floorId: id,
          floorName: id == 'F02' ? '二层' : '三层',
          availableSections: '3,13,0,-1,3-4,待定',
          queryDate: metadata ? '2026-09-08' : null,
          campus: metadata ? 1 : null,
        ),
      ),
  ],
);
Future<_Harness> _open(WidgetTester tester, {bool metadata = true}) async {
  final h = _Harness(_snapshot(1, metadata: metadata));
  addTearDown(h.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ListenableBuilder(
        listenable: h,
        builder: (_, __) => UbaaMainShell(
          user: const UserSummary(username: 'synthetic'),
          initialTab: 1,
          snapshots: {
            for (final id in FeatureId.values)
              id: id == FeatureId.classroom
                  ? h.snapshot
                  : FeatureSnapshot(feature: id),
          },
          readCacheEpoch: h.epoch,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onFeatureQuery: (_, q) async => h.queries.add(q),
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(Card, '空教室查询'));
  await tester.pumpAndSettle();
  await openQueryPanel(tester);
  await tester.enterText(find.widgetWithText(TextField, '日期'), '2026-09-08');
  h.snapshot = _snapshot(2, metadata: metadata);
  h.notifyListeners();
  await tester.pumpAndSettle();
  return h;
}

String _text(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;
Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.text('应用筛选'));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String tooltip, String item) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

Future<void> _campus(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButton<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
