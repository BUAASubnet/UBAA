import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../flow_test.dart' show app, opened;
import '../support.dart';
import 'view_support.dart';

Future<void> chooseExport(WidgetTester tester) async {
  await selectAgendaMenu(tester, '导出日历');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('包含已完成事项'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('缺少学期时明确本机范围并继续交付文件', (tester) async {
    final backend = MemoryAgenda();
    final service = await opened(backend);
    var saved = false;
    await tester.pumpWidget(
      app(
        service,
        term: '',
        saveFile: (value, name, current) async {
          saved = current();
          return '日历文件已保存';
        },
      ),
    );
    await tester.pumpAndSettle();
    await selectAgendaMenu(tester, '导出日历');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('还没有学期信息，只导出所选日期内你添加的日程。'), findsOneWidget);
    await tester.tap(find.text('包含已完成事项'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(backend.lastQuery!.term, isEmpty);
  });
  testWidgets('范围快照交给文件能力，取消与权限错误分别反馈', (tester) async {
    final backend = MemoryAgenda();
    final service = await opened(backend);
    var calls = 0, denied = false;
    Future<String?> save(
      AgendaExportResult value,
      String name,
      bool Function() current,
    ) async {
      expect(current(), isTrue);
      expect(name, endsWith('.ics'));
      expect(value.exportedCount, 1);
      calls++;
      if (denied) throw StateError('合成权限拒绝');
      return '已取消保存';
    }

    await tester.pumpWidget(app(service, saveFile: save));
    await tester.pumpAndSettle();
    await chooseExport(tester);
    expect(calls, 1);
    expect(backend.exportedCompleted, isTrue);
    expect(backend.lastQuery?.route, ConnectionMode.direct);
    expect(find.textContaining('已取消保存'), findsOneWidget);
    denied = true;
    await chooseExport(tester);
    expect(calls, 2);
    expect(find.text('保存失败，请检查存储权限后重试'), findsOneWidget);
  });
  testWidgets('旧作用域的导出结果不能打开保存面板，日期面板随作用域关闭', (tester) async {
    final backend = MemoryAgenda()..exportGate = Completer();
    final service = await opened(backend);
    var calls = 0;
    Future<String?> save(
      AgendaExportResult value,
      String name,
      bool Function() current,
    ) async {
      calls++;
      return '日历文件已保存';
    }

    await tester.pumpWidget(app(service, saveFile: save));
    await tester.pumpAndSettle();
    await chooseExport(tester);
    await tester.pumpWidget(app(service, scope: 2, saveFile: save));
    backend.exportGate!.complete(
      const AgendaExportResult(
        ics: 'synthetic',
        exportedCount: 1,
        skippedUnknownTimeCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    await selectAgendaMenu(tester, '导出日历');
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.pumpWidget(app(service, scope: 3, saveFile: save));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsNothing);
  });
}
