import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/privacy.dart';

void main() {
  for (final keepAccount in [true, false]) {
    testWidgets(keepAccount ? '同账号前后台恢复后保留日程草稿并可保存' : '恢复后退出账号关闭旧日程草稿', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final accounts = await fixtures.widgetAccounts(tester);
      final backend = _Backend();
      await tester.pumpWidget(
        UbaaAppHost(
          preferenceValues: acceptedPrivacyPreferences(),
          backend: backend,
          localAccountStore: accounts,
          initialDestination: UiDestination.agenda,
        ),
      );
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agenda-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('待办').last);
      await tester.pumpAndSettle();
      final title = find.byKey(const ValueKey('agenda-title'));
      await tester.enterText(title, '返回后继续编辑');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      expect(backend.authCalls, 2);
      if (!keepAccount) {
        final shell = tester.widget<UbaaMainShell>(
          find.byType(UbaaMainShell, skipOffstage: false),
        );
        final logout = shell.onLogout();
        await accounts.settle(tester);
        await tester.pumpAndSettle();
        await logout;
        expect(title, findsNothing);
        expect(backend.storage.created, isNull);
        await tester.pumpWidget(const SizedBox());
        return;
      }
      expect(title, findsOneWidget);
      expect(tester.widget<TextFormField>(title).controller!.text, '返回后继续编辑');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agenda-editor-save')));
      await tester.pumpAndSettle();
      expect(backend.storage.created?.content.title, '返回后继续编辑');
      expect(title, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _Backend extends fixtures.FakeRecoveryBackend implements AgendaProvider {
  @override
  late final agenda = AgendaService(storage);
  final storage = _Agenda();

  @override
  Future<AuthStatus> authStatus() async {
    if (authCalls > 0) {
      // 共享账号重新绑定会暂时关闭日程服务，再打开同一账号。
      final account = agenda.accountId!;
      await agenda.close();
      await Future<void>.delayed(Duration.zero);
      await agenda.openAccount(account);
    }
    return super.authStatus();
  }
}

class _Agenda implements AgendaBackend {
  AgendaItem? created;
  @override
  Future<AgendaItem> create(AgendaDraft draft, AgendaTime now) async {
    return created = AgendaItem(
      id: 'synthetic-resume',
      content: draft.content,
      rrule: draft.rrule,
      exdates: draft.exdates,
      overrides: [],
      completions: [],
      createdAt: now,
      updatedAt: now,
      locallyModified: true,
    );
  }

  @override
  Future<void> openAccount(String accountId) async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<AgendaQueryResult> query(AgendaQuery query) async =>
      AgendaQueryResult(entries: [], sources: []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
