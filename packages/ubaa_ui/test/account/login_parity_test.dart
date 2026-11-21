import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  for (final agree in [false, true]) {
    testWidgets('未勾选时等待明确选择，选择同意=$agree', (tester) async {
      var submits = 0;
      await tester.pumpWidget(_login(accepted: false, submit: () => submits++));
      final login = find.widgetWithText(FilledButton, '登录');
      await tester.ensureVisible(login);
      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(submits, 0);
      await tester.binding.handlePopRoute();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(agree ? '同意' : '不同意'));
      await tester.pumpAndSettle();
      expect(submits, agree ? 1 : 0);
      expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, agree);
    });
  }

  testWidgets('只勾选不记录，提交时先保存同意再调用登录', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _login(
        accepted: false,
        accept: () async => calls.add('接受'),
        submit: () => calls.add('登录'),
      ),
    );
    final checkbox = find.byType(Checkbox).last;
    await tester.ensureVisible(checkbox);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    final login = find.widgetWithText(FilledButton, '登录');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(calls, ['接受', '登录']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('登录页可打开离线隐私政策全文并返回表单', (tester) async {
    await tester.pumpWidget(_login());
    final link = find.text('《隐私政策》');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyPage), findsOneWidget);
    expect(
      tester.widget<PrivacyPolicyPage>(find.byType(PrivacyPolicyPage)).policy,
      bundledPrivacyPolicy,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(UbaaLoginView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧登录忙碌时按钮及键盘完成均不再次提交', (tester) async {
    var submits = 0;
    await tester.pumpWidget(_login(loading: true, submit: () => submits++));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, '密码'),
    );
    field.onSubmitted?.call('synthetic-password');
    expect(submits, 0);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '显示密码',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('短窗口大字登录表单保留顶部安全空间并可滚到登录', (tester) async {
    tester.view.physicalSize = const Size(390, 390);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.padding = FakeViewPadding(top: 24);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(_login());
    expect(
      tester.getRect(find.text('UBAA 登录')).top,
      greaterThanOrEqualTo(24 + 32),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    final before = position.pixels;
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '登录').hitTestable(),
      findsOneWidget,
    );
    expect(position.pixels, greaterThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('选项文字与复选框每次点击仅派发一次状态变化', (tester) async {
    final rememberChanges = <bool>[];
    final autoChanges = <bool>[];
    await tester.pumpWidget(
      _login(
        rememberChanged: rememberChanges.add,
        autoChanged: autoChanges.add,
      ),
    );

    await tester.tap(find.text('记住密码'));
    await tester.pump();
    expect(rememberChanges, <bool>[true]);
    await tester.tapAt(tester.getCenter(find.byType(Checkbox).first));
    await tester.pump();
    expect(rememberChanges, <bool>[true, true]);
    await tester.tap(find.text('自动登录'));
    await tester.pump();
    expect(autoChanges, <bool>[true]);
    await tester.tapAt(tester.getCenter(find.byType(Checkbox).at(1)));
    await tester.pump();
    expect(autoChanges, <bool>[true, true]);
  });

  for (final loading in <bool>[false, true]) {
    testWidgets('忙碌或安全保险箱不可用时整组选项禁用：忙碌=$loading', (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        _login(
          loading: loading,
          persistenceAvailable: loading,
          rememberChanged: (_) => changes++,
          autoChanged: (_) => changes++,
        ),
      );

      for (final label in <String>['记住密码', '自动登录']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
      }
      for (final checkbox in find.byType(Checkbox).evaluate()) {
        await tester.tapAt(tester.getCenter(find.byWidget(checkbox.widget)));
      }
      await tester.pump();

      expect(changes, 0);
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            // 只检查“记住密码”“自动登录”两项；隐私政策勾选行单独覆盖。
            .take(2)
            .every((checkbox) => checkbox.onChanged == null),
        isTrue,
      );
    });
  }
}

Widget _login({
  bool loading = false,
  bool accepted = true,
  Future<void> Function()? accept,
  bool persistenceAvailable = true,
  VoidCallback? submit,
  ValueChanged<bool>? rememberChanged,
  ValueChanged<bool>? autoChanged,
}) => MaterialApp(
  theme: UbaaTheme.light(),
  home: UbaaLoginView(
    username: 'account-fixture',
    password: 'synthetic-password',
    captcha: '',
    rememberPassword: false,
    autoLogin: false,
    routePolicy: RoutePolicy.auto,
    error: null,
    isLoading: loading,
    credentialPersistenceAvailable: persistenceAvailable,
    onUsernameChanged: (_) {},
    onPasswordChanged: (_) {},
    onCaptchaChanged: (_) {},
    onRememberPasswordChanged: rememberChanged ?? (_) {},
    onAutoLoginChanged: autoChanged ?? (_) {},
    onSubmit: submit ?? () {},
    privacyAccepted: accepted,
    onAcceptPrivacy: accept ?? () async {},
  ),
);
