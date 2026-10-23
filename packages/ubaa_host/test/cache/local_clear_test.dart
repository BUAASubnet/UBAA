import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../../ubaa_app/test/recovery/startup_test.dart' as support;
import '../../../ubaa_app/test/recovery/backend_rebuild/fakes.dart' as base;

const _settings = YgdkReminderSettings(
  enabled: false,
  weekDoneKey: 'synthetic-week',
  termDoneKey: 'synthetic-term',
);

void main() {
  late _Backend backend;
  late _Materials materials;
  late _Grades grades;
  late _Reminders reminders;
  late _Vault vault;
  late MemoryRecentFeatureStore recents;
  late SecureLocalAccountStore accounts;
  Future<UbaaMainShell> mount(WidgetTester tester) async {
    materials = _Materials();
    final secure = SecureMaterialStore(transport: materials);
    await secure.probe();
    accounts = SecureLocalAccountStore(secure);
    await accounts.retain('fixture-user', retainSession: true);
    backend = _Backend();
    grades = _Grades();
    reminders = _Reminders();
    vault = _Vault();
    recents = MemoryRecentFeatureStore();
    for (final key in ['fixture-user', 'fixture-school', 'other']) {
      await reminders.write(key, _settings);
      await recents.write(key, [FeatureId.exam]);
    }
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: accounts,
        credentialVault: vault,
        gradeScoreStore: grades,
        reminderStore: reminders,
        recentFeatureStore: recents,
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
  }

  testWidgets('清除当前已核实账号各别名的提醒和基线，保留其他账号', (tester) async {
    final shell = await mount(tester);
    await shell.onLogoutAndClearAccount();
    expect(grades.cleared, containsAll(['fixture-user', 'fixture-school']));
    for (final key in ['fixture-user', 'fixture-school']) {
      final saved = await reminders.read(key);
      expect(await recents.read(key), isEmpty);
      expect(saved.enabled, isTrue);
      expect(saved.weekDoneKey, isNull);
      expect(saved.termDoneKey, isNull);
    }
    expect((await reminders.read('other')).weekDoneKey, 'synthetic-week');
    expect(await recents.read('other'), [FeatureId.exam]);
    expect(grades.cleared, isNot(contains('other')));
    expect((await accounts.read())!.account, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('基线清理失败仍尝试提醒清理，错误传回调用方', (tester) async {
    final shell = await mount(tester);
    grades.fail = true;
    await expectLater(shell.onLogoutAndClearAccount(), throwsA(isA<UiError>()));
    expect((await reminders.read('fixture-school')).enabled, isTrue);
    expect((await reminders.read('fixture-user')).enabled, isTrue);
    expect(vault.clears, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('提醒清理失败不能完成，其他本机清理仍执行', (tester) async {
    final shell = await mount(tester);
    reminders.failClear = true;
    await expectLater(shell.onLogoutAndClearAccount(), throwsA(isA<UiError>()));
    expect(grades.cleared, containsAll(['fixture-user', 'fixture-school']));
    expect(backend.logouts, 1);
    expect(vault.clears, 1);
    await tester.pumpWidget(const SizedBox());
  });

  for (final failure in ['index', 'key', 'cache', 'session', 'credential']) {
    testWidgets('$failure清理失败向上传播且不跳过独立偏好清理', (tester) async {
      final shell = await mount(tester);
      materials.failWrite = failure == 'index';
      materials.failDelete = failure == 'key';
      backend.failCache = failure == 'cache';
      backend.failLogout = failure == 'session';
      vault.fail = failure == 'credential';
      await expectLater(
        shell.onLogoutAndClearAccount(),
        throwsA(isA<Object>()),
      );
      expect((await reminders.read('fixture-school')).enabled, isTrue);
      expect(grades.cleared, contains('fixture-user'));
      expect(vault.clears, 1);
      await tester.pumpAndSettle();
      expect(find.byType(UbaaLoginView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('普通退出保留提醒，但旧保存和清除回调均失效', (tester) async {
    final shell = await mount(tester);
    await shell.onLogout();
    expect((await reminders.read('fixture-school')).enabled, isFalse);
    await expectLater(
      shell.onSaveYgdkReminder!(const YgdkReminderSettings()),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      shell.onLogoutAndClearAccount(),
      throwsA(isA<BackendException>()),
    );
    expect((await reminders.read('fixture-school')).enabled, isFalse);
    expect(grades.cleared, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('提醒读取在退出后返回时不交付旧值', (tester) async {
    final shell = await mount(tester);
    reminders.readGate = Completer<void>();
    final reading = shell.onLoadYgdkReminder!();
    final rejected = expectLater(reading, throwsA(isA<BackendException>()));
    await shell.onLogoutAndClearAccount();
    reminders.readGate!.complete();
    await rejected;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('本机清理未结束时阻止重新登录，重登后旧回调仍失效', (tester) async {
    final shell = await mount(tester);
    grades.gate = Completer<void>();
    final clearing = shell.onLogoutAndClearAccount();
    await tester.pumpAndSettle();
    final login = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
    login.onUsernameChanged('fixture-user');
    login.onPasswordChanged('synthetic');
    login.onSubmit();
    await tester.pumpAndSettle();
    expect(backend.loginCalls, 0);
    grades.gate!.complete();
    await clearing;
    await tester.pumpAndSettle();
    final next = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
    next.onUsernameChanged('fixture-user');
    next.onPasswordChanged('synthetic');
    next.onSubmit();
    await tester.pumpAndSettle();
    expect(backend.loginCalls, 1);
    expect(find.byType(UbaaMainShell), findsOneWidget);
    await expectLater(shell.onLogout(), throwsA(isA<BackendException>()));
    await expectLater(
      shell.onSaveRecentFeatures!([FeatureId.spoc]),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      shell.onSaveYgdkReminder!(_settings),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      shell.onLogoutAndClearAccount(),
      throwsA(isA<BackendException>()),
    );
    expect(backend.logouts, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Materials extends support.MemoryMaterials {
  bool failWrite = false, failDelete = false;
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw const SecureMaterialException();
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw const SecureMaterialException();
    await super.delete(key);
  }
}

class _Backend extends base.Backend {
  bool failCache = false, failLogout = false;
  int logouts = 0;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-user', schoolId: 'fixture-school');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
  @override
  Future<void> clearOfflineAccount() async {
    if (failCache) throw StateError('合成缓存清理失败');
  }

  @override
  Future<void> logout() async {
    logouts++;
    if (failLogout) throw StateError('合成会话清理失败');
    await super.logout();
  }
}

class _Vault extends MemoryCredentialVault {
  bool fail = false;
  int clears = 0;
  @override
  Future<void> clear() async {
    clears++;
    if (fail) throw StateError('合成凭据清理失败');
    await super.clear();
  }
}

class _Grades implements GradeScoreStore {
  final cleared = <String>[];
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline latest,
  ) async => null;
  @override
  Future<void> clearAccount(String account) async {
    cleared.add(account);
    await gate?.future;
    if (fail) throw StateError('合成基线清理失败');
  }
}

class _Reminders implements YgdkReminderStore {
  final store = MemoryYgdkReminderStore();
  bool failClear = false;
  Completer<void>? readGate;
  @override
  Future<YgdkReminderSettings> read(String key) async {
    final value = await store.read(key);
    await readGate?.future;
    return value;
  }

  @override
  Future<void> write(String key, YgdkReminderSettings value) =>
      store.write(key, value);
  @override
  Future<void> clear(String key) async {
    if (failClear) throw StateError('合成提醒清理失败');
    await store.clear(key);
  }
}
