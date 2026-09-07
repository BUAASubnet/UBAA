import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

const _profile = UserSummary(
  username: 'fixture-login',
  displayName: '合成同学',
  schoolId: 'school-fixture',
  email: 'student@example.invalid',
  phone: '00000000000',
  idCardTypeName: '合成证件类型',
);

void main() {
  testWidgets('清除确认期间换账号，旧确认不能清除新账号', (tester) async {
    final profile = ValueNotifier<UserSummary?>(_profile);
    addTearDown(profile.dispose);
    var clears = 0;
    await _mount(tester, profile, [], onClear: () async => clears++);
    await _tap(tester, '退出并清除本机账号');
    expect(find.text('清除本机账号？'), findsOneWidget);
    profile.value = const UserSummary(username: 'new-account');
    await tester.pumpAndSettle();
    await _tap(tester, '退出并清除');
    expect(clears, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('账号资料联系人默认不在文本或语义中，主动查看只影响本地且关闭后隐藏', (tester) async {
    final profile = ValueNotifier<UserSummary?>(_profile);
    addTearDown(profile.dispose);
    final semantics = tester.ensureSemantics();
    try {
      final reads = <String>[];
      await _mount(tester, profile, reads);
      await _tap(tester, '查看账号资料');
      expect(find.text('school-fixture'), findsOneWidget);
      expect(find.text('合成证件类型'), findsOneWidget);
      expect(find.text(_profile.email!), findsNothing);
      expect(find.text(_profile.phone!), findsNothing);
      expect(find.bySemanticsLabel(_profile.email!), findsNothing);
      expect(find.bySemanticsLabel(_profile.phone!), findsNothing);
      await _tap(tester, '显示邮箱');
      await _tap(tester, '显示手机');
      expect(find.text(_profile.email!), findsOneWidget);
      expect(find.text(_profile.phone!), findsOneWidget);
      expect(reads, isEmpty);
      await _tap(tester, '收起账号资料');
      await _tap(tester, '查看账号资料');
      expect(find.text(_profile.email!), findsNothing);
      expect(find.text(_profile.phone!), findsNothing);
      expect(reads, isEmpty);
      await _tap(tester, '显示邮箱');
      await _tap(tester, '今日');
      await _tap(tester, '我的');
      expect(find.text(_profile.email!), findsNothing);
      await _tap(tester, '查看账号资料');
      expect(find.text(_profile.email!), findsNothing);
      expect(reads, isEmpty);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('同账号资料更新或换账号立即移除旧内容和展开状态', (tester) async {
    final profile = ValueNotifier<UserSummary?>(_profile);
    addTearDown(profile.dispose);
    await _mount(tester, profile, []);
    await _tap(tester, '查看账号资料');
    await _tap(tester, '显示邮箱');
    profile.value = const UserSummary(
      username: 'fixture-login',
      email: 'new@example.invalid',
      phone: 'x',
    );
    await tester.pumpAndSettle();
    expect(find.text(_profile.email!), findsNothing);
    expect(find.text('new@example.invalid'), findsNothing);
    await _tap(tester, '查看账号资料');
    expect(find.text('x'), findsNothing);
    await _tap(tester, '显示邮箱');
    expect(find.text('new@example.invalid'), findsOneWidget);
    profile.value = const UserSummary(username: 'other-fixture');
    await tester.pumpAndSettle();
    expect(find.text('new@example.invalid'), findsNothing);
    await _tap(tester, '查看账号资料');
    expect(find.text('显示邮箱'), findsNothing);
    expect(find.text('显示手机'), findsNothing);
    profile.value = null;
    await tester.pumpAndSettle();
    expect(find.text('收起账号资料'), findsNothing);
    expect(find.text('查看账号资料'), findsNothing);
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
          initialTab: 3,
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
}
