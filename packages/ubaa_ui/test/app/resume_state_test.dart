import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../agenda/support.dart';

Widget app({
  required UiDestination destination,
  AgendaService? agenda,
  CloudPrintService? print,
  Future<List<PrintSource>> Function()? pick,
  bool connecting = false,
  ConnectionMode route = ConnectionMode.direct,
  String term = '2026-1',
  RoutePolicy policy = RoutePolicy.auto,
  String account = 'fixture',
}) => MaterialApp(
  theme: UbaaTheme.light(),
  home: UbaaMainShell(
    user: null,
    cacheAccountId: account,
    snapshots: const {},
    routePolicy: policy,
    activeRoutes: [route],
    agendaSchoolRoute: route,
    agenda: AgendaAccess(service: agenda, term: term),
    cloudPrintService: print,
    onPickPrintFiles: pick,
    connecting: connecting,
    initialDestination: destination,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) async {},
  ),
);

void main() {
  testWidgets('自动恢复路线和学期后保留新建日程草稿并可保存', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = MemoryAgenda();
    final service = AgendaService(backend);
    await service.openAccount('fixture');
    await tester.pumpWidget(
      app(destination: UiDestination.agenda, agenda: service),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待办').last);
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('agenda-title'));
    await tester.enterText(title, '回到前台后继续填写');
    await tester.pumpWidget(
      app(
        destination: UiDestination.agenda,
        agenda: service,
        connecting: true,
        route: ConnectionMode.webvpn,
        term: '',
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      app(
        destination: UiDestination.agenda,
        agenda: service,
        route: ConnectionMode.webvpn,
      ),
    );
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
    expect(tester.widget<TextFormField>(title).controller!.text, '回到前台后继续填写');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-editor-save')));
    await tester.pumpAndSettle();
    expect(backend.items.values.single.content.title, '回到前台后继续填写');
  });

  testWidgets('日程重新查询期间保留列表，完成后替换结果，换账号立即清除', (tester) async {
    final backend = MemoryAgenda();
    final service = AgendaService(backend);
    await service.openAccount('fixture');
    await service.create(
      AgendaDraft(
        content: AgendaContent(
          kind: AgendaKind.task,
          title: '保留的日程',
          allDay: false,
        ),
        exdates: [],
      ),
      AgendaTime(
        rfc3339: '2026-11-16T09:00:00+08:00',
        timezone: 'Asia/Shanghai',
      ),
    );
    await tester.pumpWidget(
      app(destination: UiDestination.agenda, agenda: service),
    );
    await tester.pumpAndSettle();
    expect(find.text('保留的日程'), findsOneWidget);
    backend.gate = Completer<AgendaQueryResult>();
    await tester.pumpWidget(
      app(
        destination: UiDestination.agenda,
        agenda: service,
        route: ConnectionMode.webvpn,
        term: '',
      ),
    );
    await tester.pump();
    expect(find.text('保留的日程'), findsOneWidget);
    backend.gate!.complete(AgendaQueryResult(entries: [], sources: []));
    await tester.pumpAndSettle();
    expect(find.text('保留的日程'), findsNothing);
    backend.gate = null;
    await tester.pumpWidget(
      app(destination: UiDestination.agenda, agenda: service),
    );
    await tester.pumpAndSettle();
    expect(find.text('保留的日程'), findsOneWidget);
    await tester.pumpWidget(
      app(destination: UiDestination.agenda, account: 'other'),
    );
    await tester.pumpAndSettle();
    expect(find.text('保留的日程'), findsNothing);
  });

  for (final (changeAccount, replaceService, label) in [
    (false, false, '恢复连接后继续显示打印设置'),
    (false, true, '更换同账号服务后使用新服务上传'),
    (true, false, '切换账号停止上传'),
  ]) {
    testWidgets('选文件时$label', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PrintService();
      final restored = replaceService ? PrintService() : service;
      final selected = Completer<List<PrintSource>>();
      var released = 0;
      Future<List<PrintSource>> pick() => selected.future;
      await tester.pumpWidget(
        app(destination: UiDestination.campus, print: service, pick: pick),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('图书馆云打印'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('上传文件'));
      await tester.pump();
      await tester.pumpWidget(
        app(
          destination: UiDestination.campus,
          print: restored,
          pick: pick,
          connecting: true,
          account: changeAccount ? 'other' : 'fixture',
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        app(
          destination: UiDestination.campus,
          print: restored,
          pick: pick,
          account: changeAccount ? 'other' : 'fixture',
        ),
      );
      selected.complete([
        PrintSource(
          path: '/synthetic/a.pdf',
          name: 'a.pdf',
          release: () async {
            released++;
          },
        ),
      ]);
      await tester.pumpAndSettle();
      expect(service.uploads, 0);
      if (changeAccount) {
        expect(find.text('确认上传'), findsNothing);
      } else {
        expect(find.text('确认上传'), findsOneWidget);
        await tester.tap(find.text('确认上传'));
        await tester.pumpAndSettle();
        expect(restored.uploads, 1);
        if (replaceService) expect(service.uploads, 0);
      }
      expect(released, 1);
    });
  }
}

class PrintService implements CloudPrintService {
  int uploads = 0;
  @override
  bool get isCurrent => true;
  @override
  Future<List<PrintDocument>> documents({required bool scans}) async => [];
  @override
  Future<List<UiError?>> upload(
    List<PrintSource> sources,
    PrintOptions options,
  ) async {
    uploads++;
    return [for (final _ in sources) null];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
