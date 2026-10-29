import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../support/libbook/backend.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final width in [402.0, 900.0]) {
    testWidgets(
      '座位刷新同步重读楼馆和分区汇总且保留所选日期 $width',
      (tester) async {
        final backend = await _open(tester, width: width);
        await _secondDay(tester);
        final before = backend.libraryReads.length;
        final selected = backend.libraryReads.last;
        backend.refreshedFree = 7;
        await _tap(tester, find.byTooltip('刷新当前查询'));
        expect(backend.libraryReads.skip(before).map((q) => q.view), [
          FeatureQueryView.summary,
          FeatureQueryView.libbookAreas,
          FeatureQueryView.libbookAreaDetail,
          FeatureQueryView.libbookSeats,
        ]);
        expect(backend.libraryReads.last.hasSameParameters(selected), isTrue);
        expect(backend.libraryReads[before].date, selected.date);
        expect(find.textContaining('一层 · 空 7/20'), findsWidgets);
        expect(find.textContaining('空 7/10'), findsWidgets);
        expect(backend.preparedSeats, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
    testWidgets('进入分区自动读取首日首时段并只显示可预约座位 $width', (tester) async {
      final backend = await _open(tester, width: width);
      expect(backend.libraryReads.map((q) => q.view), [
        FeatureQueryView.summary,
        FeatureQueryView.libbookAreas,
        FeatureQueryView.libbookAreaDetail,
        FeatureQueryView.libbookSeats,
      ]);
      final query = backend.libraryReads.last;
      expect(query.date, DateTime(2026, 9, 4));
      expect(
        [query.segment, query.startTime, query.endTime],
        ['first-slot', '08:00', '10:00'],
      );
      expect(find.widgetWithText(Card, 'A1'), findsOneWidget);
      expect(find.widgetWithText(Card, 'A2'), findsNothing);
      expect(find.widgetWithText(Card, 'A3'), findsNothing);
      expect(backend.preparedSeats, isEmpty);
      expect(backend.commitCalls, 0);
    });
  }
  testWidgets(
    '汇总刷新失败不继续读取座位，也不清空已有馆区选择',
    (tester) async {
      final backend = await _open(tester);
      final before = backend.libraryReads.length;
      backend.failNext = true;
      await _tap(tester, find.byTooltip('刷新当前查询'));
      expect(backend.libraryReads.skip(before).map((q) => q.view), [
        FeatureQueryView.summary,
      ]);
      expect(find.text('重试'), findsOneWidget);
      expect(backend.preparedSeats, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    '刷新汇总挂起后离开页面不再扩展分区座位读取',
    (tester) async {
      final backend = await _open(tester);
      final before = backend.libraryReads.length;
      final gate = Completer<void>();
      backend.pending = gate;
      await tester.tap(find.byTooltip('刷新当前查询'));
      await tester.pump();
      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(backend.libraryReads.skip(before).map((q) => q.view), [
        FeatureQueryView.summary,
      ]);
      expect(
        find.widgetWithText(Card, FeatureId.libbook.title),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    '刷新后座位不可预约时清除原选择且展示可用座位为空',
    (tester) async {
      final backend = await _open(tester);
      await _tap(tester, find.widgetWithText(Card, 'A1'));
      backend.noAvailableSeats = true;
      await _tap(tester, find.byTooltip('刷新当前查询'));
      expect(find.text('当前分区暂无可预约座位'), findsOneWidget);
      expect(find.text('已选座位：A1'), findsNothing);
      expect(find.text('预约此座位'), findsNothing);
      expect(backend.preparedSeats, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets('窄屏大字和键盘占位下可滚动选择座位并直接提交', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    final backend = await _open(tester, width: 360);
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    await _tap(tester, find.text('预约此座位'));
    expect(backend.preparedSeats.single.seatId, 'canonical-seat-0');
    expect(backend.commitCalls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('正文切换日期自动取同日时段且准备保留完整canonical目标', (tester) async {
    final backend = await _open(tester);
    final before = backend.libraryReads.length;
    await _secondDay(tester);
    expect(backend.libraryReads, hasLength(before + 1));
    final query = backend.libraryReads.last;
    expect(query.date, DateTime(2026, 9, 5));
    expect(
      [query.segment, query.startTime, query.endTime],
      ['second-slot', '14:00', '16:00'],
    );
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    await _tap(tester, find.text('预约此座位'));
    final action = backend.preparedSeats.single;
    expect(
      [
        action.areaId,
        action.seatId,
        action.day,
        action.segment,
        action.startTime,
        action.endTime,
      ],
      [
        'library-a-floor-1-area-1',
        'canonical-seat-0',
        '2026-09-05',
        'second-slot',
        '14:00',
        '16:00',
      ],
    );
    expect(backend.commitCalls, 1);
  });
  testWidgets('同日切换时段自动查询且清除原座位选择', (tester) async {
    final backend = await _open(
      tester,
      days: [
        LibbookDaySchedulePresentation(
          day: '2026-09-04',
          timeSlots: [
            ..._defaultDays.first.timeSlots,
            ..._defaultDays.last.timeSlots,
          ],
        ),
      ],
    );
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    await _tap(tester, find.byKey(const ValueKey('libbook-choice-时段')));
    await _tap(tester, find.text('次日时段 14:00–16:00').last);
    expect(backend.libraryReads.last.segment, 'second-slot');
    expect(backend.libraryReads.last.date, DateTime(2026, 9, 4));
    expect(find.text('已选座位：A1'), findsNothing);
  });
  for (final parent in ['楼馆', '楼层', '分区']) {
    testWidgets('切换$parent 自动加载新分区座位且清除旧选择', (tester) async {
      final backend = await _open(tester, width: 402);
      await _tap(tester, find.widgetWithText(Card, 'A1'));
      if (parent == '楼馆') await _tap(tester, find.byTooltip('切换楼馆'));
      await _tap(tester, switch (parent) {
        '楼馆' => find.widgetWithText(CheckedPopupMenuItem<String>, '合成乙馆'),
        '楼层' => find.textContaining('二层 · 空 2/20').last,
        _ => find.textContaining('安静阅览区 2').last,
      });
      expect(backend.libraryReads.last.view, FeatureQueryView.libbookSeats);
      expect(backend.libraryReads.last.areaId, switch (parent) {
        '楼馆' => 'library-b-floor-1-area-1',
        '楼层' => 'library-a-floor-2-area-1',
        _ => 'library-a-floor-1-area-2',
      });
      expect(find.text('已选座位：A1'), findsNothing);
      expect(backend.preparedSeats, isEmpty);
    });
  }
  testWidgets('切换日期挂起时旧座位失效，返回后迟到结果不扩展读取链', (tester) async {
    final backend = await _open(tester);
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    await _tap(tester, find.byKey(const ValueKey('libbook-choice-日期')));
    final gate = Completer<void>();
    backend.pending = gate;
    await tester.tap(find.text('9月5日').last);
    await tester.pump();
    expect(find.text('已选座位：A1'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    final before = backend.libraryReads.length;
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Card, FeatureId.libbook.title), findsOneWidget);
    expect(backend.libraryReads, hasLength(before));
    expect(backend.preparedSeats, isEmpty);
  });
  for (final entry in <String, List<LibbookDaySchedulePresentation>>{
    '当前分区暂无可用日期。': [],
    '当前日期暂无可用时段。': [
      const LibbookDaySchedulePresentation(day: '2026-09-04', timeSlots: []),
    ],
    '时段信息不完整或重复，请刷新后重试。': [
      const LibbookDaySchedulePresentation(
        day: '2026-09-04',
        timeSlots: [
          LibbookTimeSlotPresentation(
            id: 'broken',
            start: '08:00',
            end: '',
            label: '缺失',
          ),
        ],
      ),
    ],
    '日期信息无法唯一确认，请刷新后重试。': [_defaultDays.first, _defaultDays.first],
  }.entries) {
    testWidgets('不完整日程不猜查询参数：${entry.key}', (tester) async {
      final backend = await _open(tester, days: entry.value);
      expect(
        find.text(entry.key),
        entry.key.contains('不完整') || entry.key.contains('唯一')
            ? findsNothing
            : findsOneWidget,
      );
      expect(
        backend.libraryReads.where(
          (q) => q.view == FeatureQueryView.libbookSeats,
        ),
        isEmpty,
      );
      expect(backend.preparedSeats, isEmpty);
    });
  }
  testWidgets('座位失败显示重试并保留同一日期时段', (tester) async {
    final backend = await _open(tester);
    backend.failNext = true;
    await _secondDay(tester);
    final requested = backend.libraryReads.last;
    expect(find.text('重试'), findsOneWidget);
    await _tap(tester, find.text('重试'));
    expect(backend.libraryReads.last.hasSameParameters(requested), isTrue);
    expect(find.widgetWithText(Card, 'A1'), findsOneWidget);
    expect(backend.preparedSeats, isEmpty);
  });
}

Future<void> _secondDay(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('libbook-choice-日期')));
  await _tap(tester, find.text('9月5日').last);
}

class _ScheduleBackend extends LibraryBackend {
  _ScheduleBackend({super.state, this.days = _defaultDays});
  final List<LibbookDaySchedulePresentation> days;
  bool noAvailableSeats = false;
  int? refreshedFree;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    final result = await super.loadFeatureQuery(feature, query);
    if (refreshedFree != null &&
        {
          FeatureQueryView.summary,
          FeatureQueryView.libbookAreas,
        }.contains(query.view)) {
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          for (final d in result.details)
            FeatureDetail(
              title: d.title,
              presentation: switch (d.presentation) {
                LibbookLibraryPresentation p => LibbookLibraryPresentation(
                  id: p.id,
                  name: p.name,
                  queryDate: p.queryDate,
                  freeNum: refreshedFree!,
                  totalNum: p.totalNum,
                  storeys: [
                    for (final f in p.storeys)
                      LibbookStoreyPresentation(
                        id: f.id,
                        name: f.name,
                        freeNum: refreshedFree!,
                        totalNum: f.totalNum,
                      ),
                  ],
                ),
                LibbookAreaPresentation p => LibbookAreaPresentation(
                  id: p.id,
                  name: p.name,
                  areaName: p.areaName,
                  premisesId: p.premisesId,
                  storeyId: p.storeyId,
                  freeNum: refreshedFree!,
                  totalNum: p.totalNum,
                  queryDate: p.queryDate,
                ),
                _ => d.presentation,
              },
            ),
        ],
      );
    }
    if (noAvailableSeats && query.view == FeatureQueryView.libbookSeats) {
      return FeatureResult.success(
        summary: '合成不可预约座位',
        resolvedRoute: ConnectionMode.direct,
        details: result.details
            .where(
              (d) => (d.presentation! as LibbookSeatPresentation).status != 1,
            )
            .toList(),
      );
    }
    if (result.details.isEmpty ||
        feature != FeatureId.libbook ||
        query.view != FeatureQueryView.libbookAreaDetail) {
      return result;
    }
    return FeatureResult.success(
      summary: '合成分区日程',
      resolvedRoute: ConnectionMode.direct,
      details: [
        FeatureDetail(
          title: '错误展示分区',
          presentation: LibbookAreaSchedulePresentation(
            id: query.areaId!,
            name: '合成分区',
            days: days,
          ),
        ),
      ],
    );
  }
}

Future<_ScheduleBackend> _open(
  WidgetTester tester, {
  double width = 900,
  String state = 'normal',
  List<LibbookDaySchedulePresentation> days = _defaultDays,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = _ScheduleBackend(state: state, days: days);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialDestination: UiDestination.campus,
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.libbook.title));
  return backend;
}

const _defaultDays = [
  LibbookDaySchedulePresentation(
    day: '2026-09-04',
    timeSlots: [
      LibbookTimeSlotPresentation(
        id: 'first-slot',
        start: '08:00',
        end: '10:00',
        label: '首日时段',
      ),
    ],
  ),
  LibbookDaySchedulePresentation(
    day: '2026-09-05',
    timeSlots: [
      LibbookTimeSlotPresentation(
        id: 'second-slot',
        start: '14:00',
        end: '16:00',
        label: '次日时段',
      ),
    ],
  ),
];

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
