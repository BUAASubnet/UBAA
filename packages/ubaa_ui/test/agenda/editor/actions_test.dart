import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../flow_test.dart' show app, opened;
import '../support.dart';
import 'pickers_support.dart';

AgendaTime time(String value) =>
    AgendaTime(rfc3339: value, timezone: 'Asia/Shanghai');
final fixed = time('2026-11-05T09:00:00+08:00');

Future<void> saveEditor(WidgetTester tester) => saveAgendaEditor(tester);

void main() {
  testWidgets('明确修改跳过日期时替换系列排除日期', (tester) async {
    final backend = MemoryAgenda();
    final service = await opened(backend);
    final item = await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.event,
          title: '假期调整',
          allDay: false,
          start: fixed,
          end: time('2026-11-05T10:00:00+08:00'),
        ),
        rrule: 'FREQ=DAILY;COUNT=5',
        exdates: [time('2026-11-08T09:00:00+08:00')],
      ),
      fixed,
    );
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('假期调整'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑事项'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '全部'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('agenda-skips')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('agenda-editor-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('agenda-skips')),
      '2026-11-07',
    );
    await saveEditor(tester);
    expect(
      backend.items[item.id]!.exdates.single.rfc3339,
      '2026-11-07T09:00:00+08:00',
    );
  });
  for (final scope in {
    AgendaEditScope.thisOccurrence: '仅此次',
    AgendaEditScope.thisAndFuture: '此次及以后',
    AgendaEditScope.all: '全部',
  }.entries) {
    testWidgets('重复事项按${scope.value}编辑和删除，保存失败保留输入', (tester) async {
      final backend = MemoryAgenda();
      final service = await opened(backend);
      await service.create(
        AgendaDraft(
          content: AgendaContent(
            kind: AgendaKind.event,
            title: '重复合成事项',
            allDay: false,
            start: fixed,
            end: time('2026-11-05T10:00:00+08:00'),
          ),
          rrule: 'FREQ=DAILY;COUNT=3',
          exdates: [],
        ),
        fixed,
      );
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重复合成事项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑事项'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, scope.value));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('agenda-title')),
        '范围修改',
      );
      backend.failWrite = true;
      await saveEditor(tester);
      expect(backend.items.values.single.content.title, '重复合成事项');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('agenda-title')))
            .controller!
            .text,
        '范围修改',
      );
      await tester.scrollUntilVisible(
        find.text('保存失败，原事项保持，请重试'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('agenda-editor-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('保存失败，原事项保持，请重试').hitTestable(), findsOneWidget);
      backend.failWrite = false;
      await saveEditor(tester);
      expect(backend.lastEdit, scope.key);
      expect(find.text('范围修改'), findsOneWidget);
      await tester.tap(find.text('范围修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除事项'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, scope.value));
      await tester.pumpAndSettle();
      expect(backend.lastDelete, scope.key);
      expect(backend.items, isEmpty);
    });
  }

  testWidgets('学校事项保存本地备注、隐藏与完成，保留上游状态和原详情导航', (tester) async {
    final backend = MemoryAgenda();
    final timing = AgendaTiming(kind: AgendaTimingKind.deadline, due: fixed);
    backend.school.add(
      SchoolAgendaItem(
        key: SchoolAgendaKey(source: 'spoc', upstreamId: 'synthetic-a'),
        timing: timing,
        title: '合成学校作业',
        subtitle: '合成课程',
        statusLabel: '未提交',
        upstreamStatus: AgendaUpstreamStatus(
          feature: AgendaFeature.spoc,
          completed: false,
          submission: AgendaSubmission.unsubmitted,
        ),
        navigation: AgendaNavigation(
          feature: AgendaFeature.spoc,
          assignmentId: 'synthetic-a',
        ),
        homeTodo: true,
      ),
    );
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(backend.overlays.values.single.value.completedAt, isNotNull);
    await tester.tap(find.text('合成学校作业'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('未提交')),
      findsOneWidget,
    );
    await tester.tap(find.text('添加备注…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '备注'), '本机计划');
    await tester.pump();
    await tester.tap(find.text('保存备注'));
    await tester.pumpAndSettle();
    expect(backend.overlays.values.single.value.note, '本机计划');
    expect(backend.overlays.values.single.value.completedAt, isNotNull);
    await tester.tap(find.text('合成学校作业'));
    await tester.pumpAndSettle();
    expect(find.text('查看原页面'), findsOneWidget);
    await tester.tap(find.text('隐藏事项'));
    await tester.pumpAndSettle();
    expect(backend.overlays.values.single.value.hidden, isTrue);
    await tester.tap(find.byTooltip('筛选日程'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '显示已隐藏'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '显示已隐藏'))
          .value,
      isTrue,
    );
    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();
    expect(find.text('合成学校作业'), findsOneWidget);
    expect(backend.school.single.upstreamStatus.completed, isFalse);
  });
}
