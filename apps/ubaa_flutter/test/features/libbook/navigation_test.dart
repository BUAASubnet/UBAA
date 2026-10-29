import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../support/libbook/backend.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final state in ['normal', 'missing-parents', 'conflicting-parents']) {
    testWidgets('图书馆父标识 $state 仅沿合法分区自动加载', (tester) async {
      final backend = await _open(tester, state: state);
      expect(
        backend.libraryReads.last.view,
        state == 'conflicting-parents'
            ? FeatureQueryView.libbookAreas
            : FeatureQueryView.libbookSeats,
      );
      if (state == 'missing-parents') {
        final original = libraryData(backend.libraryReads[1], state);
        final area =
            original.details.first.presentation! as LibbookAreaPresentation;
        expect(area.premisesId, isEmpty);
        expect(area.storeyId, isEmpty);
      }
      expect(backend.preparedSeats, isEmpty);
      expect(backend.commitCalls, 0);
    });
  }
  testWidgets(
    '图书馆隐藏后首页刷新不能触发后台自动分区链',
    (tester) async {
      final backend = await _open(tester, width: 1280);
      await tapVisibleWithScroll(tester, find.byIcon(Icons.home_outlined));
      final before = backend.libraryReads.length;
      await tapVisibleWithScroll(tester, find.byTooltip('刷新'));
      expect(backend.libraryReads, hasLength(before));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets('明确空座位后重新加载不复活原选择', (tester) async {
    final backend = await _open(tester);
    await tapVisibleWithScroll(tester, find.widgetWithText(Card, 'A1'));
    backend.emptyNext = true;
    await tapVisibleWithScroll(tester, find.byTooltip('刷新当前查询'));
    expect(find.text('已选座位：A1'), findsNothing);
    await tapVisibleWithScroll(tester, find.byTooltip('刷新当前查询'));
    expect(find.widgetWithText(Card, 'A1'), findsOneWidget);
    expect(find.text('已选座位：A1'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets('换楼馆沿新父项自动加载且返回仍为图书馆菜单', (tester) async {
    final backend = await _open(tester);
    await tapVisibleWithScroll(tester, find.widgetWithText(Card, 'A1'));
    await tapVisibleWithScroll(tester, find.byTooltip('切换楼馆'));
    await tapVisibleWithScroll(
      tester,
      find.widgetWithText(CheckedPopupMenuItem<String>, '合成乙馆'),
    );
    expect(backend.libraryReads.last.areaId, 'library-b-floor-1-area-1');
    expect(find.text('已选座位：A1'), findsNothing);
    await tapVisibleWithScroll(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, FeatureId.libbook.title), findsOneWidget);
    expect(backend.preparedSeats, isEmpty);
  });
  testWidgets('我的预约仍沿分页上下文读取且不准备写入', (tester) async {
    final backend = await _open(tester);
    await tapVisibleWithScroll(tester, find.text('我的预约'));
    expect(backend.libraryReads.last.view, FeatureQueryView.libbookBookings);
    expect(backend.preparedBookings, isEmpty);
  });
}

Future<LibraryBackend> _open(
  WidgetTester tester, {
  double width = 402,
  String state = 'normal',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = LibraryBackend(state: state);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialDestination: UiDestination.campus,
    ),
  );
  await tester.pumpAndSettle();
  await tapVisibleWithScroll(
    tester,
    find.widgetWithText(Card, FeatureId.libbook.title),
  );
  return backend;
}

Future<void> tapVisibleWithScroll(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
