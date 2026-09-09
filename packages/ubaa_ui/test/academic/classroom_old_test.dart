import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../coursework_content_test.dart' show showFeature;
import '../support/navigation.dart';

FeatureDetail room(
  String title, {
  String floor = '教学楼',
  String id = 'F',
  String sections = '1,3,13',
}) => FeatureDetail(
  title: title,
  fields: const [FeatureField(label: '原字段', value: '保留值')],
  presentation: ClassroomPresentation(
    roomId: 'ID-$title',
    floorId: id,
    floorName: floor,
    availableSections: sections,
    queryDate: '2026-09-09',
    campus: 2,
  ),
);
void main() {
  testWidgets('大字横滚表格时长楼栋标题保持在可视宽度内', (tester) async {
    final name = List.filled(4, '合成较长教学楼名称').join();
    await showFeature(
      tester,
      FeatureId.classroom,
      [room('长名教室', floor: name)],
      [],
      size: const Size(390, 844),
      textScale: 1.3,
    );
    expect(tester.getRect(find.text(name)).right, lessThanOrEqualTo(374));
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    await tester.drag(horizontal, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.text('14').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('长名教室')).left, greaterThanOrEqualTo(16));
    expect(tester.getRect(find.text('教室')).left, greaterThanOrEqualTo(16));
    expect(tester.getRect(find.text(name)).left, greaterThanOrEqualTo(16));
    expect(tester.getRect(find.text(name)).right, lessThanOrEqualTo(374));
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧教室节次表三端同列，正文不常驻楼层筛选或节次芯片', (tester) async {
    await showFeature(
      tester,
      FeatureId.classroom,
      [room('A101'), room('B202', floor: '第二教学楼', id: 'F2')],
      [],
      size: const Size(390, 844),
    );
    expect(find.text('教室'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('第13节'), findsNothing);
    expect(find.text('当前页楼层'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    final row = tester.getRect(find.byKey(const ValueKey('classroom-row-0')));
    expect(row.height, lessThanOrEqualTo(50));
    expect(tester.getRect(find.text('14')).right, lessThanOrEqualTo(390));
    await tester.tap(find.text('A101'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('ID-A101'), findsOneWidget);
    expect(find.text('1,3,13'), findsOneWidget);
    expect(find.text('保留值'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('同楼名不同floorId不拆组，无服务端分页时全部教室可连续滚动', (tester) async {
    await showFeature(
      tester,
      FeatureId.classroom,
      [for (var i = 0; i < 42; i++) room('合成教室$i', id: 'F$i')],
      [],
      size: const Size(834, 1000),
    );
    expect(find.text('教学楼'), findsOneWidget);
    expect(find.byTooltip('下一页'), findsNothing);
    final scroll = find.byType(Scrollable).hitTestable().last;
    await tester.scrollUntilVisible(
      find.text('合成教室41'),
      300,
      scrollable: scroll,
    );
    expect(find.text('合成教室41'), findsOneWidget);
    expect(find.text('14').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('校区按旧名称呈现，筛选收起保留草稿和本地搜索', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(tester, FeatureId.classroom, [
      room('目标教室'),
      room('其他教室'),
    ], queries);
    await openQueryPanel(tester);
    expect(find.text('学院路'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), 'ID-目标教室');
    await closeQueryPanel(tester);
    expect(find.text('目标教室'), findsOneWidget);
    expect(find.text('其他教室'), findsNothing);
    await openQueryPanel(tester);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
          .controller!
          .text,
      'ID-目标教室',
    );
    expect(queries, isEmpty);
  });
}
