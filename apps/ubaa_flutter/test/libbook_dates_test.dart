import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../integration_test/ui_library/backend.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('图书馆自然选择第二天原时段后精确查询且无需手输', (tester) async {
    final backend = await _open(tester);
    final before = backend.libraryReads.length;
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(find.byKey(const ValueKey('libbook-choice-日期')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('libbook-choice-日期')));
    await _tap(tester, find.text('2026-09-05').last);
    await _tap(tester, find.byKey(const ValueKey('libbook-choice-时段')));
    await _tap(tester, find.text('次日时段 14:00–16:00').last);
    expect(backend.libraryReads, hasLength(before));
    expect(find.widgetWithText(TextField, '日期'), findsNothing);
    await _tap(tester, find.text('查询座位'));
    expect(backend.libraryReads, hasLength(before + 1));
    final query = backend.libraryReads.last;
    expect(query.view, FeatureQueryView.libbookSeats);
    expect(query.areaId, 'library-a-floor-1-area-1');
    expect(query.date, DateTime(2026, 9, 5));
    expect(query.segment, 'second-slot');
    expect(query.startTime, '14:00');
    expect(query.endTime, '16:00');
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    await _tap(tester, find.text('准备预约此座位'));
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
    await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
    expect(backend.libraryReads.last, same(query));
    expect(backend.commitCalls, 0);
  });

  testWidgets('日期时段草稿关闭再开保持原值且不发读取', (tester) async {
    final backend = await _open(tester, width: 402);
    final before = backend.libraryReads.length;
    await _selectSecond(tester);
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(_choice(tester, '日期').value, '2026-09-05');
    expect(_choice(tester, '时段').value, 'second-slot');
    expect(backend.libraryReads, hasLength(before));
    expect(find.widgetWithText(TextField, '日期'), findsNothing);
  });

  testWidgets('清除时段与日期立即取消旧座位动作且关闭返回不复活', (tester) async {
    final backend = await _open(tester);
    await _queryAndSelect(tester);
    final before = backend.libraryReads.length;
    await _tap(tester, find.byTooltip('搜索与筛选'));
    await _tap(tester, find.byTooltip('清除时段'));
    expect(_choice(tester, '时段').value, isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('libbook-query-seats')),
          )
          .onPressed,
      isNull,
    );
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.text('已选座位：A1'), findsNothing);
    expect(find.text('准备预约此座位'), findsNothing);
    await _tap(tester, find.byTooltip('搜索与筛选'));
    await _tap(tester, find.byTooltip('清除日期'));
    expect(_choice(tester, '日期').value, isNull);
    expect(find.byKey(const ValueKey('libbook-choice-时段')), findsNothing);
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(backend.libraryReads, hasLength(before));
    await _tap(tester, find.byTooltip('返回'));
    expect(find.widgetWithText(Card, '预约座位'), findsOneWidget);
    await _tap(tester, find.widgetWithText(Card, '预约座位'));
    expect(find.text('已选座位：A1'), findsNothing);
    expect(find.text('准备预约此座位'), findsNothing);
    expect(backend.preparedSeats, isEmpty);
    expect(backend.commitCalls, 0);
  });

  testWidgets('换日期保留当前楼馆楼层分区并清掉原时段与座位', (tester) async {
    final backend = await _open(tester);
    await _queryAndSelect(tester);
    final before = backend.libraryReads.length;
    await _tap(tester, find.byTooltip('搜索与筛选'));
    await _tap(tester, find.byKey(const ValueKey('libbook-choice-日期')));
    await _tap(tester, find.text('2026-09-04').last);
    expect(_choice(tester, '楼馆').value, 'library-a');
    expect(_choice(tester, '楼层').value, 'library-a-floor-1');
    expect(_choice(tester, '分区').value, 'library-a-floor-1-area-1');
    expect(_choice(tester, '时段').value, isNull);
    expect(_choice(tester, '时段').items!.map((item) => item.value), [
      'first-slot',
    ]);
    expect(backend.libraryReads, hasLength(before));
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.text('已选座位：A1'), findsNothing);
    expect(find.widgetWithText(Card, 'A1'), findsNothing);
    expect(find.text('准备预约此座位'), findsNothing);
  });

  for (final parent in ['楼馆', '楼层', '分区']) {
    testWidgets('切换$parent 清掉日期时段与旧座位且不自动查询座位', (tester) async {
      final backend = await _open(tester);
      await _queryAndSelect(tester);
      await _tap(tester, find.byTooltip('搜索与筛选'));
      await _tap(tester, find.byKey(ValueKey('libbook-choice-$parent')));
      await _tap(tester, switch (parent) {
        '楼馆' => find.text('合成乙馆 3/40').last,
        '楼层' => find.text('二层 2/20').last,
        _ => find.textContaining('安静阅览区 2').last,
      });
      expect(_choice(tester, '日期').value, isNull);
      expect(find.byKey(const ValueKey('libbook-choice-时段')), findsNothing);
      expect(
        backend.libraryReads.where(
          (q) => q.view == FeatureQueryView.libbookSeats,
        ),
        hasLength(1),
      );
      expect(
        backend.libraryReads.last.view,
        FeatureQueryView.libbookAreaDetail,
      );
      expect(backend.libraryReads.last.areaId, switch (parent) {
        '楼馆' => 'library-b-floor-1-area-1',
        '楼层' => 'library-a-floor-2-area-1',
        _ => 'library-a-floor-1-area-2',
      });
      await _tap(tester, find.widgetWithText(TextButton, '完成'));
      expect(find.text('准备预约此座位'), findsNothing);
      expect(find.text('已选座位：A1'), findsNothing);
      expect(backend.preparedSeats, isEmpty);
    });
  }

  testWidgets('座位查询未完成时返回，迟到结果不恢复旧座位或后台读取', (tester) async {
    final backend = await _open(tester);
    await _selectSecond(tester);
    final gate = Completer<void>();
    backend.pending = gate;
    await tester.tap(find.byKey(const ValueKey('libbook-query-seats')));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '完成'));
    await tester.pump();
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    final before = backend.libraryReads.length;
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Card, '预约座位'), findsOneWidget);
    expect(find.widgetWithText(Card, 'A1'), findsNothing);
    expect(backend.libraryReads, hasLength(before));
    expect(backend.preparedSeats, isEmpty);
  });

  testWidgets('日期为空时不猜日期且查询按钮不可用', (tester) async {
    final backend = await _open(tester, days: const []);
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(find.text('当前分区暂无可用日期。'), findsOneWidget);
    expect(_choice(tester, '日期').items, isEmpty);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('libbook-query-seats')),
          )
          .onPressed,
      isNull,
    );
    expect(
      backend.libraryReads.where(
        (q) => q.view == FeatureQueryView.libbookSeats,
      ),
      isEmpty,
    );
  });

  for (final incomplete in [false, true]) {
    testWidgets(incomplete ? '畸形时段不能形成查询参数' : '日期有值但空时段时明确展示空结果', (
      tester,
    ) async {
      await _open(
        tester,
        days: [
          LibbookDaySchedulePresentation(
            day: '2026-09-04',
            timeSlots: incomplete
                ? const [
                    LibbookTimeSlotPresentation(
                      id: 'broken',
                      start: '08:00',
                      end: '',
                      label: '字段缺失',
                    ),
                  ]
                : const [],
          ),
        ],
      );
      await _tap(tester, find.byTooltip('搜索与筛选'));
      await _tap(tester, find.byKey(const ValueKey('libbook-choice-日期')));
      await _tap(tester, find.text('2026-09-04').last);
      expect(
        find.text(incomplete ? '时段信息不完整或重复，请刷新后重试。' : '当前日期暂无可用时段。'),
        findsOneWidget,
      );
      expect(_choice(tester, '时段').items, isEmpty);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('libbook-query-seats')),
            )
            .onPressed,
        isNull,
      );
    });
  }

  testWidgets('重复日期不能任取第一条或合并时段', (tester) async {
    await _open(tester, days: [_defaultDays.first, _defaultDays.first]);
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(find.text('日期信息无法唯一确认，请刷新后重试。'), findsOneWidget);
    expect(_choice(tester, '日期').items, isEmpty);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('libbook-query-seats')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('明确冲突的父分区不可点选', (tester) async {
    final backend = await _open(tester, state: 'conflicting-parents');
    await _tap(tester, find.byTooltip('搜索与筛选'));
    expect(find.byKey(const ValueKey('libbook-choice-分区')), findsNothing);
    expect(find.byKey(const ValueKey('libbook-choice-日期')), findsNothing);
    expect(backend.libraryReads.last.view, FeatureQueryView.libbookAreas);
  });

  testWidgets('分区缺少父字段仍可自然选择第二天', (tester) async {
    final backend = await _open(tester, state: 'missing-parents');
    await _selectSecond(tester);
    await _tap(tester, find.byKey(const ValueKey('libbook-query-seats')));
    expect(backend.libraryReads.last.date, DateTime(2026, 9, 5));
    expect(backend.libraryReads.last.segment, 'second-slot');
  });

  testWidgets('座位查询失败保留明确日期时段并可用原值重试', (tester) async {
    final backend = await _open(tester);
    await _selectSecond(tester);
    backend.failNext = true;
    await _tap(tester, find.byKey(const ValueKey('libbook-query-seats')));
    expect(_choice(tester, '日期').value, '2026-09-05');
    expect(_choice(tester, '时段').value, 'second-slot');
    final failedQuery = backend.libraryReads.last;
    await _tap(tester, find.byKey(const ValueKey('libbook-query-seats')));
    expect(backend.libraryReads.last.hasSameParameters(failedQuery), isTrue);
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.widgetWithText(Card, 'A1'), findsOneWidget);
    expect(backend.preparedSeats, isEmpty);
  });

  testWidgets('高级跨分区查询失败后正文重试显示原参数座位', (tester) async {
    final backend = await _open(tester);
    await _selectSecond(tester);
    await _tap(tester, find.text('更多查询'));
    final area = find.widgetWithText(TextField, '分区 ID');
    await tester.ensureVisible(area);
    await tester.enterText(area, 'library-b-floor-1-area-1');
    backend.failNext = true;
    await _tap(tester, find.text('应用筛选'));
    final requested = backend.libraryReads.last;
    final callsBeforeRetry = backend.libraryReads.length;
    expect(requested.view, FeatureQueryView.libbookSeats);
    expect(requested.areaId, 'library-b-floor-1-area-1');
    expect(requested.date, DateTime(2026, 9, 5));
    expect(requested.segment, 'second-slot');
    expect(requested.startTime, '14:00');
    expect(requested.endTime, '16:00');
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.text('重试'), findsOneWidget);
    await _tap(tester, find.text('重试'));
    expect(backend.libraryReads, hasLength(callsBeforeRetry + 1));
    expect(backend.libraryReads.last.hasSameParameters(requested), isTrue);
    expect(find.widgetWithText(Card, 'A1'), findsOneWidget);
    await _tap(tester, find.widgetWithText(Card, 'A1'));
    await _tap(tester, find.text('准备预约此座位'));
    expect(backend.preparedSeats.single.areaId, requested.areaId);
    expect(backend.preparedSeats.single.seatId, 'canonical-seat-0');
    await _tap(tester, find.widgetWithText(OutlinedButton, '取消'));
    expect(backend.commitCalls, 0);

    await _tap(tester, find.byTooltip('搜索与筛选'));
    await _tap(tester, find.byKey(const ValueKey('libbook-choice-日期')));
    await _tap(tester, find.text('2026-09-04').last);
    await _tap(tester, find.widgetWithText(TextButton, '完成'));
    expect(find.widgetWithText(Card, 'A1'), findsNothing);
    expect(find.text('准备预约此座位'), findsNothing);
    expect(backend.libraryReads, hasLength(callsBeforeRetry + 1));
  });
}

class _ScheduleBackend extends LibraryBackend {
  _ScheduleBackend({super.state, this.days = _defaultDays});
  final List<LibbookDaySchedulePresentation> days;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    final result = await super.loadFeatureQuery(feature, query);
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
      initialTab: 1,
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.widgetWithText(Card, FeatureId.libbook.title));
  await _tap(tester, find.widgetWithText(Card, '预约座位'));
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

DropdownButton<String> _choice(WidgetTester tester, String label) =>
    tester.widget<DropdownButton<String>>(
      find.byKey(ValueKey('libbook-choice-$label')),
    );

Future<void> _selectSecond(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('搜索与筛选'));
  await _tap(tester, find.byKey(const ValueKey('libbook-choice-日期')));
  await _tap(tester, find.text('2026-09-05').last);
  await _tap(tester, find.byKey(const ValueKey('libbook-choice-时段')));
  await _tap(tester, find.text('次日时段 14:00–16:00').last);
}

Future<void> _queryAndSelect(WidgetTester tester) async {
  await _selectSecond(tester);
  await _tap(tester, find.byKey(const ValueKey('libbook-query-seats')));
  await _tap(tester, find.widgetWithText(TextButton, '完成'));
  await _tap(tester, find.widgetWithText(Card, 'A1'));
  expect(find.text('已选座位：A1'), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
