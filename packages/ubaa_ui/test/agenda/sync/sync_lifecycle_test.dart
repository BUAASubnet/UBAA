import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/view.dart';
import '../support.dart';
import '../data_sheet_support.dart';

const merged = AgendaSyncReport(
  status: AgendaSyncStatus.upToDate,
  pendingCount: 0,
  changedCount: 1,
);
const done = AgendaSyncReport(
  status: AgendaSyncStatus.upToDate,
  pendingCount: 0,
  changedCount: 0,
);
const needsCreation = AgendaSyncReport(
  status: AgendaSyncStatus.locationUnknown,
  pendingCount: 1,
  changedCount: 0,
);
final time = AgendaTime(
  rfc3339: '2026-11-05T09:00:00+08:00',
  timezone: 'Asia/Shanghai',
);

class Backend extends MemoryAgenda implements AgendaSyncBackend {
  bool enabled = true;
  @override
  Future<bool> syncEnabled() async => enabled;
  @override
  Future<int> unsyncedCount() async => items.length + overlays.length;
  String? account;
  final calls = <(String?, AgendaSyncAction)>[];
  Completer<AgendaSyncReport>? first;
  Future<AgendaSyncReport> Function()? push;
  AgendaFailure? creationFailure;
  Object? pullError;
  AgendaSyncReport result = done;
  @override
  Future<void> openAccount(String id) async {
    account = id;
  }

  @override
  Future<void> deactivate() async {
    account = null;
  }

  @override
  AgendaSyncJob prepareSync(AgendaSyncAction action, AgendaTime now) {
    final failure = creationFailure;
    if (action == AgendaSyncAction.createConfirmed && failure != null) {
      throw AgendaException(failure);
    }
    return () => sync(action, now);
  }

  Future<AgendaSyncReport> sync(AgendaSyncAction action, AgendaTime now) async {
    if (action == AgendaSyncAction.createConfirmed) enabled = true;
    calls.add((account, action));
    if (calls.length == 1 && first != null) return first!.future;
    if (action == AgendaSyncAction.push && push != null) return push!();
    if (action == AgendaSyncAction.pull && pullError != null) throw pullError!;
    return result;
  }
}

Widget view(
  AgendaService? service, {
  bool visible = true,
  int scope = 1,
  int? projection,
  ConnectionMode route = ConnectionMode.direct,
  VoidCallback? changed,
}) => AgendaView(
  service: service,
  scopeKey: scope,
  projectionKey: projection,
  route: route,
  term: 'synthetic',
  onOpenSchool: (_) {},
  visible: visible,
  now: DateTime.utc(2026, 11, 5, 9),
  onChanged: changed,
);
Widget app(
  AgendaService? service, {
  bool visible = true,
  ConnectionMode route = ConnectionMode.direct,
}) => MaterialApp(
  home: Scaffold(
    body: view(service, visible: visible, route: route),
  ),
);
void size(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('同账号服务恢复保留编辑草稿并使用新服务保存', (tester) async {
    size(tester);
    final previous = MemoryAgenda();
    final service = AgendaService(previous);
    await service.openAccount('fixture-a');
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待办').last);
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('agenda-title'));
    await tester.enterText(title, '恢复期间保留的草稿');
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(title).controller!.text, '恢复期间保留的草稿');
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('agenda-editor-save')),
          )
          .onPressed,
      isNull,
    );
    final next = MemoryAgenda();
    final restored = AgendaService(next);
    await restored.openAccount('fixture-a');
    await tester.pumpWidget(app(restored));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(title).controller!.text, '恢复期间保留的草稿');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-editor-save')));
    await tester.pumpAndSettle();
    expect(previous.writes, 0);
    expect(next.items.values.single.content.title, '恢复期间保留的草稿');
  });

  testWidgets('客户端忙时直接反馈并且不打开创建确认', (tester) async {
    size(tester);
    final backend = Backend()
      ..result = needsCreation
      ..creationFailure = AgendaFailure.unavailable;
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, '创建云端日程'));
    await tester.pumpAndSettle();
    expect(find.text('确认创建'), findsNothing);
    expect(find.text('正在同步，请稍后再试'), findsOneWidget);
    expect(backend.calls.map((call) => call.$2), [AgendaSyncAction.pull]);
  });

  testWidgets('失败的拉取撤下旧创建入口并要求重新拉取', (tester) async {
    size(tester);
    final backend = Backend()..result = needsCreation;
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    backend.pullError = StateError('合成路线不可用');
    await expectLater(
      service.sync(AgendaSyncAction.pull, time),
      throwsStateError,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '创建云端日程'), findsNothing);
    backend.pullError = null;
    await tester.tap(find.widgetWithText(FilledButton, '刷新'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '创建云端日程'), findsOneWidget);
    expect(
      backend.calls.map((call) => call.$2),
      List.filled(3, AgendaSyncAction.pull),
    );
  });

  testWidgets('上传失败后显示已经合并到本机的事项', (tester) async {
    size(tester);
    final backend = Backend();
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    backend.push = () async {
      await backend.create(
        AgendaDraft(
          content: AgendaContent(
            kind: AgendaKind.task,
            title: '上传失败前已合并的事项',
            allDay: false,
          ),
          exdates: [],
        ),
        time,
      );
      throw StateError('合成上传失败');
    };
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, '同步'));
    await tester.pumpAndSettle();
    await closeAgendaDataSheet(tester);
    expect(find.text('上传失败前已合并的事项').hitTestable(), findsOneWidget);
    expect(backend.calls.map((call) => call.$2), [
      AgendaSyncAction.pull,
      AgendaSyncAction.push,
    ]);
  });
  testWidgets('旧账号的创建确认不能对新账号发出创建动作', (tester) async {
    size(tester);
    final backend = Backend()..result = needsCreation;
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, '创建云端日程'));
    await tester.pumpAndSettle();
    expect(find.text('确认创建'), findsOneWidget);
    await service.close();
    await service.openAccount('fixture-b');
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, '确认创建');
    expect(confirm, findsNothing);
    expect(
      backend.calls.where(
        (call) => call.$2 == AgendaSyncAction.createConfirmed,
      ),
      isEmpty,
    );
  });
  testWidgets('有效路线变化撤销旧创建确认', (tester) async {
    size(tester);
    final backend = Backend()..result = needsCreation;
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await openAgendaDataSheet(tester);
    await tester.tap(find.widgetWithText(FilledButton, '创建云端日程'));
    await tester.pumpAndSettle();
    expect(find.text('确认创建'), findsOneWidget);
    await tester.pumpWidget(app(service, route: ConnectionMode.webvpn));
    await tester.pumpAndSettle();
    expect(find.text('确认创建'), findsNothing);
    expect(backend.calls.map((call) => call.$2), [
      AgendaSyncAction.pull,
      AgendaSyncAction.pull,
    ]);
  });
  testWidgets('后台合并后回到保留状态的日程页应读取已落库的事项', (tester) async {
    size(tester);
    final backend = Backend()..first = Completer<AgendaSyncReport>();
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(service, visible: false));
    await tester.pumpAndSettle();
    await backend.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.task,
          title: '后台合并到本机的事项',
          allDay: false,
        ),
        exdates: [],
      ),
      time,
    );
    backend.first!.complete(merged);
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(backend.calls.length, 2, reason: '重新打开触发一次只读同步');
    expect(find.text('后台合并到本机的事项'), findsOneWidget);
  });
  testWidgets('同账号同路线的异步合并不应关闭未保存的编辑器', (tester) async {
    size(tester);
    final backend = Backend()..first = Completer<AgendaSyncReport>();
    final service = AgendaService(backend);
    await service.openAccount('fixture-a');
    var projection = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, redraw) => view(
              service,
              projection: projection,
              changed: () => redraw(() => projection++),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-create')));
    await tester.pumpAndSettle();
    // 宽屏编辑器是对话框，背后的日程页也有“待办”；取最上层。
    await tester.tap(find.text('待办').last);
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('agenda-title'));
    await tester.enterText(title, '未保存的合成草稿');
    backend.first!.complete(merged);
    await tester.pumpAndSettle();
    expect(projection, 2, reason: '模拟生产 onChanged 更新投影代次');
    expect(title, findsOneWidget);
    expect(tester.widget<TextFormField>(title).controller!.text, '未保存的合成草稿');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-editor-save')));
    await tester.pumpAndSettle();
    expect(backend.items.values.single.content.title, '未保存的合成草稿');
  });
}
