import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'flow_test.dart' show app, opened;
import 'support.dart';

const unknown = AgendaSyncReport(
  status: AgendaSyncStatus.outcomeUnknown,
  pendingCount: 2,
  changedCount: 0,
);
const missing = AgendaSyncReport(
  status: AgendaSyncStatus.locationUnknown,
  pendingCount: 2,
  changedCount: 0,
);
const done = AgendaSyncReport(
  status: AgendaSyncStatus.upToDate,
  pendingCount: 0,
  changedCount: 0,
);

class SyncAgenda extends MemoryAgenda implements AgendaSyncBackend {
  final calls = <AgendaSyncAction>[];
  AgendaSyncReport result = unknown;
  @override
  AgendaSyncJob prepareSync(AgendaSyncAction action, AgendaTime now) =>
      () => sync(action, now);

  Future<AgendaSyncReport> sync(AgendaSyncAction action, AgendaTime now) async {
    calls.add(action);
    return result;
  }
}

void main() {
  testWidgets('本机投影刷新不再次拉取，同账号重新登录才使用新的同步作业', (tester) async {
    final backend = SyncAgenda()..result = done;
    final service = await opened(backend);
    await tester.pumpWidget(app(service, scope: 1));
    await tester.pumpAndSettle();
    expect(backend.calls, [AgendaSyncAction.pull]);
    await tester.pumpWidget(app(service, scope: 2));
    await tester.pumpAndSettle();
    expect(backend.calls, [AgendaSyncAction.pull], reason: '日程和缓存投影变化只刷新本机数据');
    await service.close();
    await service.openAccount('synthetic');
    await tester.pumpWidget(app(service, scope: 3));
    await tester.pumpAndSettle();
    expect(backend.calls, [AgendaSyncAction.pull, AgendaSyncAction.pull]);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
  testWidgets('打开页面拉取一次，未知结果只在用户核对时再次读取', (tester) async {
    final backend = SyncAgenda();
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(backend.calls, [AgendaSyncAction.pull]);
    expect(find.text('上次云端操作结果待核对，2 条修改待同步'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '核对云端'));
    await tester.pumpAndSettle();
    expect(backend.calls, [AgendaSyncAction.pull, AgendaSyncAction.pull]);
    await tester.pumpAndSettle();
    expect(backend.calls, [AgendaSyncAction.pull, AgendaSyncAction.pull]);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
  testWidgets('范围未知时取消创建不写入，确认后创建并显示同步结果', (tester) async {
    final backend = SyncAgenda()..result = missing;
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '创建云端日程'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(backend.calls, [AgendaSyncAction.pull]);
    await tester.tap(find.widgetWithText(TextButton, '创建云端日程'));
    await tester.pumpAndSettle();
    backend.result = done;
    await tester.tap(find.widgetWithText(FilledButton, '确认创建'));
    await tester.pumpAndSettle();
    expect(backend.calls, [
      AgendaSyncAction.pull,
      AgendaSyncAction.createConfirmed,
    ]);
    expect(find.text('日程已同步'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
  testWidgets('未验证状态保留待同步数量且关闭云端操作', (tester) async {
    final backend = SyncAgenda()
      ..result = const AgendaSyncReport(
        status: AgendaSyncStatus.unverified,
        pendingCount: 3,
        changedCount: 0,
      );
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.text('云端同步暂不可用，3 条修改保存在本机'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '同步'))
          .onPressed,
      isNull,
    );
    expect(backend.calls, [AgendaSyncAction.pull]);
    await tester.pumpWidget(const SizedBox());
    await service.dispose();
  });
}
