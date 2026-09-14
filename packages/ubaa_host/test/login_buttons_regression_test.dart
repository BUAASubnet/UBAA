import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  _registerRecoveryRegressions();

  testWidgets('登录页项目链接确实交给宿主打开且不触发登录', (tester) async {
    final information = _AppInformation();
    await tester.pumpWidget(_host(information));
    await tester.pumpAndSettle();

    final link = find.text('开源项目: github.com/BUAASubnet/UBAA');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(information.opened, <AppLink>[AppLink.project]);
    expect(find.byType(UbaaLoginView), findsOneWidget);
  });

  testWidgets('登录选项文字与复选框一样可点并保持记住与自动的联动', (tester) async {
    await tester.pumpWidget(_host(_AppInformation()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自动登录'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isTrue);

    await tester.tap(find.text('记住密码'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isFalse);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isFalse);
  });

  testWidgets('已保存的手动登录恢复遮罩密码且点击登录前不认证', (tester) async {
    final backend = _CountingBackend();
    await tester.pumpWidget(
      _host(
        _AppInformation(),
        backend: backend,
        vault: MemoryCredentialVault(initial: _savedCredential),
      ),
    );
    await tester.pumpAndSettle();

    final password = tester.widget<TextField>(
      find.widgetWithText(TextField, '密码'),
    );
    expect(password.obscureText, isTrue);
    expect(password.controller!.text, _savedCredential.password);
    expect(backend.loginCalls, 0);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(backend.loginCalls, 1);
    expect(find.byType(UbaaMainShell), findsOneWidget);
  });

  testWidgets('凭据保存失败在首页只提示一次且不重复登录', (tester) async {
    final backend = _CountingBackend();
    final vault = _FailingVault()..failSave = true;
    await tester.pumpWidget(
      _host(_AppInformation(), backend: backend, vault: vault),
    );
    await tester.pumpAndSettle();
    await _fillLogin(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(find.byType(UbaaLoginView), findsNothing);
    expect(find.text('已登录，但账号密码未能保存，下次需要重新输入。'), findsOneWidget);
    expect(find.text('登录失败'), findsNothing);
    expect(backend.loginCalls, 1);
    expect(vault.saveAttempts, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();

    expect(find.text('已登录，但账号密码未能保存，下次需要重新输入。'), findsNothing);
    expect(backend.loginCalls, 1);
    expect(vault.saveAttempts, 1);
  });

  testWidgets('登录期间后台恢复不能吞掉已经确认登录的保存失败提示', (tester) async {
    final backend = _CountingBackend()..loginGate = Completer<void>();
    final vault = _FailingVault()..failSave = true;
    var factoryCalls = 0;
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () =>
            ++factoryCalls == 1 ? backend : _SignedInBackend(),
        credentialVault: vault,
        reminderStore: MemoryYgdkReminderStore(),
        gradeScoreStore: MemoryGradeScoreStore(),
        appInformation: _AppInformation(),
      ),
    );
    await tester.pumpAndSettle();
    await _fillLogin(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();
    for (final state in <AppLifecycleState>[
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(factoryCalls, 1);
    backend.loginGate!.complete();
    await tester.pumpAndSettle();

    expect(factoryCalls, 2);
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(find.text('已登录，但账号密码未能保存，下次需要重新输入。'), findsOneWidget);
    expect(backend.loginCalls, 1);
    expect(vault.saveAttempts, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('已登录，但账号密码未能保存，下次需要重新输入。'), findsNothing);
  });

  for (final failGradeClear in <bool>[false, true]) {
    testWidgets('退出清除保险箱失败仍清理成绩并隐藏已登录信息：成绩删除失败=$failGradeClear', (
      tester,
    ) async {
      final vault = _FailingVault(initial: _savedCredential)..failClear = true;
      final grades = _RecordingGradeStore()..failClear = failGradeClear;
      await tester.pumpWidget(
        _host(
          _AppInformation(),
          backend: _SignedInBackend(),
          vault: vault,
          grades: grades,
        ),
      );
      await tester.pumpAndSettle();
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Drawer), matching: find.text('设置')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('退出并清除本机账号'));
      await tester.tap(find.text('退出并清除本机账号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出并清除'));
      await tester.pumpAndSettle();

      expect(grades.clearedAccounts, <String>['fixture-student']);
      expect(find.byType(UbaaMainShell), findsNothing);
      expect(find.byType(UbaaLoginView), findsOneWidget);
      expect(find.text('fixture-private-name'), findsNothing);
      expect(find.text('本机数据未能完全清除，请稍后重试。'), findsOneWidget);
      expect(find.textContaining('合成系统错误'), findsNothing);
      expect(vault.hasValue, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('登录项目链接失败可复制并重试且保持输入', (tester) async {
    final information = _AppInformation()..failOpen = true;
    final backend = _CountingBackend();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_host(information, backend: backend));
    await tester.pumpAndSettle();
    await _fillLogin(tester);
    final link = find.text('开源项目: github.com/BUAASubnet/UBAA');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.text('链接未能打开'), findsOneWidget);
    expect(find.textContaining('合成系统错误'), findsNothing);
    await tester.tap(find.text('复制地址'));
    await tester.pumpAndSettle();
    expect(copied, AppLink.project.url);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '学号'))
          .controller!
          .text,
      'fixture-student',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '密码'))
          .controller!
          .text,
      'fixture-password',
    );
    information.failOpen = false;
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(information.opened, <AppLink>[AppLink.project, AppLink.project]);
    expect(find.text('链接未能打开'), findsNothing);
    expect(backend.loginCalls, 0);
    expect(find.byType(UbaaLoginView), findsOneWidget);
  });

  testWidgets('项目链接在途不重复打开且离开登录后迟到失败不显示旧对话框', (tester) async {
    final information = _AppInformation()..pending = Completer<bool>();
    final backend = _CountingBackend();
    await tester.pumpWidget(_host(information, backend: backend));
    await tester.pumpAndSettle();
    await _fillLogin(tester);
    final link = find.text('开源项目: github.com/BUAASubnet/UBAA');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    await tester.tap(link);
    await tester.pump();
    expect(information.opened, <AppLink>[AppLink.project]);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    information.pending!.complete(false);
    await tester.pumpAndSettle();

    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(find.text('链接未能打开'), findsNothing);
    expect(backend.loginCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('登录忙碌时项目入口和选项文字都不可重复操作', (tester) async {
    final information = _AppInformation();
    final backend = _CountingBackend()..loginGate = Completer<void>();
    await tester.pumpWidget(_host(information, backend: backend));
    await tester.pumpAndSettle();
    await _fillLogin(tester);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();
    await tester.tap(find.text('记住密码'));
    await tester.tap(find.text('自动登录'));
    await tester.tap(find.text('开源项目: github.com/BUAASubnet/UBAA'));
    await tester.pump();

    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isFalse);
    expect(information.opened, isEmpty);
    expect(backend.loginCalls, 1);
    backend.loginGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);
  });
}

void _registerRecoveryRegressions() {
  for (final rejection in <UbaaErrorCode>[
    UbaaErrorCode.invalidCredentials,
    UbaaErrorCode.networkError,
  ]) {
    testWidgets('R3：自动登录 $rejection 期间后台恢复不重发且可手动重试', (tester) async {
      final state = _RecoveryState()..rejection = rejection;
      final first = _RecoveryBackend(state)..loginGate = Completer<void>();
      final vault = _FailingVault(
        initial: _recoveryCredential.copyWith(autoLogin: true),
      )..failClear = true;
      var factories = 0;
      await tester.pumpWidget(
        UbaaAppHost(
          backendFactory: () =>
              ++factories == 1 ? first : _RecoveryBackend(state),
          credentialVault: vault,
          reminderStore: MemoryYgdkReminderStore(),
          gradeScoreStore: MemoryGradeScoreStore(),
          appInformation: _AppInformation(),
        ),
      );
      await first.loginStarted.future;
      await _backgroundAndResume(tester);
      first.loginGate!.complete();
      await tester.pumpAndSettle();

      expect(factories, 2);
      expect(state.loginCalls, 1);
      final login = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
      expect(login.error?.code, rejection);
      expect(login.password, isEmpty);
      expect(vault.hasValue, isTrue);
      state.rejection = null;
      await tester.enterText(
        find.widgetWithText(TextField, '密码'),
        'fixture-corrected-password',
      );
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(state.loginCalls, 2);
      expect(find.byType(UbaaMainShell), findsOneWidget);
    });
  }

  for (final failures in <({bool clear, bool logout})>[
    (clear: false, logout: false),
    (clear: true, logout: false),
    (clear: false, logout: true),
  ]) {
    final failClear = failures.clear;
    testWidgets(
      'R1：确认退出清除后后台恢复仍完成清理并如实反馈：删除失败=$failClear，注销失败=${failures.logout}',
      (tester) async {
        final state = _RecoveryState()
          ..signedIn = true
          ..failLogout = failures.logout;
        final first = _RecoveryBackend(state)..logoutGate = Completer<void>();
        final vault = _FailingVault(initial: _recoveryCredential)
          ..failClear = failClear;
        final grades = _RecordingGradeStore();
        var factories = 0;
        await tester.pumpWidget(
          UbaaAppHost(
            backendFactory: () =>
                ++factories == 1 ? first : _RecoveryBackend(state),
            credentialVault: vault,
            reminderStore: MemoryYgdkReminderStore(),
            gradeScoreStore: grades,
            appInformation: _AppInformation(),
          ),
        );
        await tester.pumpAndSettle();
        await _confirmClearFromSettings(tester);
        await first.logoutStarted.future;
        await _backgroundAndResume(tester);
        await tester.pumpAndSettle();
        final factoriesWhileClearing = factories;
        first.logoutGate!.complete();
        await tester.pumpAndSettle();

        expect(factoriesWhileClearing, 1);
        expect(factories, 2);
        expect(find.byType(UbaaMainShell), findsNothing);
        expect(find.byType(UbaaLoginView), findsOneWidget);
        expect(vault.clearAttempts, 1);
        expect(vault.hasValue, failClear);
        expect(grades.clearedAccounts, <String>['fixture-old-account']);
        expect(
          find.text('本机数据未能完全清除，请稍后重试。'),
          failClear ? findsOneWidget : findsNothing,
        );
        expect(
          tester.widget<UbaaLoginView>(find.byType(UbaaLoginView)).password,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('R2：登录页改填账号后后台恢复保持新账号且不回填旧密码', (tester) async {
    final state = _RecoveryState();
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () => _RecoveryBackend(state),
        credentialVault: MemoryCredentialVault(initial: _recoveryCredential),
        reminderStore: MemoryYgdkReminderStore(),
        gradeScoreStore: MemoryGradeScoreStore(),
        appInformation: _AppInformation(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '学号'),
      'fixture-new-account',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '密码'),
      'fixture-new-password',
    );
    await tester.pump();

    await _backgroundAndResume(tester);
    await tester.pumpAndSettle();

    final login = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
    expect(login.username, 'fixture-new-account');
    expect(login.password, isEmpty);
    expect(state.loginCalls, 0);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '学号'))
          .controller!
          .text,
      'fixture-new-account',
    );
  });
}

Future<void> _backgroundAndResume(WidgetTester tester) async {
  for (final state in <AppLifecycleState>[
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

Future<void> _confirmClearFromSettings(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text('设置')),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('退出并清除本机账号'));
  await tester.tap(find.text('退出并清除本机账号'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('退出并清除'));
  await tester.pump();
}

const _recoveryCredential = Credential(
  username: 'fixture-old-account',
  password: 'fixture-old-password',
);

Widget _host(
  _AppInformation information, {
  UbaaBackend? backend,
  CredentialVault? vault,
  GradeScoreStore? grades,
}) => UbaaAppHost(
  backend: backend ?? DemoBackend(loginDelay: Duration.zero),
  credentialVault: vault ?? MemoryCredentialVault(),
  gradeScoreStore: grades,
  appInformation: information,
);

class _AppInformation implements PlatformAppInformation {
  final opened = <AppLink>[];
  bool failOpen = false;
  Completer<bool>? pending;

  @override
  Future<bool> open(AppLink link) async {
    opened.add(link);
    if (failOpen) throw StateError('合成系统错误');
    return pending?.future ?? true;
  }

  @override
  Future<String?> version() async => '合成版本';
}

const _savedCredential = Credential(
  username: 'fixture-student',
  password: 'fixture-password',
);

Future<void> _fillLogin(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, '学号'),
    'fixture-student',
  );
  await tester.enterText(
    find.widgetWithText(TextField, '密码'),
    'fixture-password',
  );
  await tester.pump();
}

class _CountingBackend extends DemoBackend {
  _CountingBackend() : super(loginDelay: Duration.zero);
  int loginCalls = 0;
  Completer<void>? loginGate;

  @override
  Future<void> login(LoginInput input) async {
    loginCalls++;
    await loginGate?.future;
    await super.login(input);
  }
}

class _SignedInBackend extends DemoBackend {
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async => const UserSummary(
    username: 'fixture-student',
    displayName: 'fixture-private-name',
  );
}

class _FailingVault extends MemoryCredentialVault {
  _FailingVault({super.initial});
  bool failSave = false;
  bool failClear = false;
  int saveAttempts = 0;
  int clearAttempts = 0;

  @override
  Future<void> save(Credential credential) async {
    saveAttempts++;
    if (failSave) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
    await super.save(credential);
  }

  @override
  Future<void> clear() async {
    clearAttempts++;
    if (failClear) throw StateError('合成系统错误');
    await super.clear();
  }
}

class _RecoveryState {
  bool signedIn = false;
  bool failLogout = false;
  int loginCalls = 0;
  UbaaErrorCode? rejection;
}

class _RecoveryBackend implements UbaaBackend {
  _RecoveryBackend(this.state);
  final _RecoveryState state;
  final loginStarted = Completer<void>();
  final logoutStarted = Completer<void>();
  Completer<void>? loginGate;
  Completer<void>? logoutGate;

  @override
  Future<AuthStatus> authStatus() async =>
      state.signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => state.signedIn
      ? const UserSummary(username: 'fixture-old-account', displayName: '合成用户')
      : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    state.loginCalls++;
    if (!loginStarted.isCompleted) loginStarted.complete();
    await loginGate?.future;
    if (state.rejection case final code?) throw BackendException(code);
    state.signedIn = true;
  }

  @override
  Future<void> logout() async {
    if (!logoutStarted.isCompleted) logoutStarted.complete();
    await logoutGate?.future;
    if (state.failLogout) throw StateError('合成注销失败');
    state.signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
}

class _RecordingGradeStore implements GradeScoreStore {
  final clearedAccounts = <String>[];
  bool failClear = false;

  @override
  Future<GradeScoreBaseline?> read(
    String account,
    ConnectionMode route,
  ) async => null;

  @override
  Future<void> write(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) async {}

  @override
  Future<void> clearAccount(String account) async {
    clearedAccounts.add(account);
    if (failClear) throw StateError('合成系统错误');
  }
}
