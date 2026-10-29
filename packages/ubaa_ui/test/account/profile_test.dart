import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

const _profile = UserSummary(
  username: 'fixture-login',
  displayName: '合成同学',
  schoolId: 'school-fixture',
  email: 's***t@example.invalid',
  phone: '000****0000',
  idCardTypeName: '合成证件类型',
);

void main() {
  testWidgets('相同本机归属从遮罩变为在线姓名不会重置资料路由', (tester) async {
    final profile = ValueNotifier<UserSummary?>(
      const UserSummary(username: 'f***r', accountScope: 'same'),
    );
    addTearDown(profile.dispose);
    await _mount(tester, profile, []);
    profile.value = const UserSummary(
      username: 'fixture-user',
      accountScope: 'same',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '我的资料'), findsOneWidget);
    expect(find.text('fixture-user'), findsOneWidget);
  });

  testWidgets('遮罩资料保持联系人保护且在线更新不退出个人页', (tester) async {
    final profile = ValueNotifier<UserSummary?>(
      UserSummary(
        username: 'f***r',
        displayName: '合***名',
        schoolId: 'T***1',
        accountScope: 'local-account',
        profileRoute: ConnectionMode.webvpn,
        profileEvidence: DataEvidence(
          accountId: 'local-account',
          origin: DataOrigin.persisted,
          fetchedAt: DateTime(2026, 9, 22, 8),
          complete: true,
          savedForOffline: true,
        ),
        profileNotice: '资料暂未更新，保留上次内容',
      ),
    );
    addTearDown(profile.dispose);
    await _mount(tester, profile, []);
    expect(find.text('合***名'), findsWidgets);
    expect(find.text('资料暂未更新，保留上次内容'), findsOneWidget);
    profile.value = const UserSummary(
      username: 'fixture-user',
      accountScope: 'local-account',
      displayName: '线上合成姓名',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '我的资料'), findsOneWidget);
    expect(find.text('fixture-user'), findsOneWidget);
  });

  testWidgets('清除确认期间换账号，旧确认不能清除新账号', (tester) async {
    final profile = ValueNotifier<UserSummary?>(_profile);
    addTearDown(profile.dispose);
    var clears = 0;
    await _mount(tester, profile, [], onClear: () async => clears++);
    await openUtility(tester, '设置');
    await _tap(tester, '退出并清除本机账号');
    expect(find.text('清除本机账号？'), findsOneWidget);
    profile.value = const UserSummary(username: 'new-account');
    await tester.pumpAndSettle();
    await _tap(tester, '退出并清除');
    expect(clears, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('资料直接显示上游遮罩联系人，返回再进入不触发读取', (tester) async {
    final profile = ValueNotifier<UserSummary?>(_profile);
    addTearDown(profile.dispose);
    final reads = <String>[];
    await _mount(tester, profile, reads);
    expect(find.text('school-fixture'), findsOneWidget);
    expect(find.text(_profile.email!), findsOneWidget);
    expect(find.text(_profile.phone!), findsOneWidget);
    expect(reads, isEmpty);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await openUtility(tester, '我的资料');
    expect(find.text(_profile.email!), findsOneWidget);
    expect(find.text(_profile.phone!), findsOneWidget);
    expect(reads, isEmpty);
  });

  testWidgets('同账号资料更新立即替换内容，换账号和退出移除旧内容', (tester) async {
    final profile = ValueNotifier<UserSummary?>(_profile);
    addTearDown(profile.dispose);
    await _mount(tester, profile, []);
    profile.value = const UserSummary(
      username: 'fixture-login',
      email: 'new@example.invalid',
      phone: 'x',
    );
    await tester.pumpAndSettle();
    expect(find.text(_profile.email!), findsNothing);
    expect(find.text('x'), findsOneWidget);
    expect(find.text('new@example.invalid'), findsOneWidget);
    profile.value = const UserSummary(username: 'other-fixture');
    await tester.pumpAndSettle();
    expect(find.text('new@example.invalid'), findsNothing);
    await openUtility(tester, '我的资料');
    expect(find.text('other-fixture'), findsOneWidget);
    profile.value = null;
    await tester.pumpAndSettle();
    expect(find.text(_profile.email!), findsNothing);
    expect(find.text('new@example.invalid'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  ValueNotifier<UserSummary?> profile,
  List<String> reads, {
  Future<void> Function()? onClear,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1100);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: ValueListenableBuilder<UserSummary?>(
        valueListenable: profile,
        builder: (context, user, _) => UbaaMainShell(
          initialDestination: UiDestination.home,
          user: user,
          snapshots: {
            for (final feature in FeatureId.values)
              feature: FeatureSnapshot(feature: feature),
          },
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async => reads.add('refresh'),
          onRetryFeature: (_) async => reads.add('retry'),
          onFeatureQuery: (_, _) async => reads.add('query'),
          onLogout: () async {},
          onLogoutAndClearAccount: onClear ?? () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openUtility(tester, '我的资料');
}
