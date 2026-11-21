import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/privacy.dart';

final _updateUrl = Uri.parse('https://example.invalid/update');
final _detailUrl = Uri.parse('https://example.invalid/detail');

AppAnnouncement _announcement(String id, AppAnnouncementLevel level) =>
    AppAnnouncement(
      id: id,
      level: level,
      title: '合成公告 $id',
      body: '合成正文',
      linkUrl: _detailUrl,
      linkText: '查看详情',
      startsAt: DateTime(2020),
    );

void main() {
  testWidgets('门控生效时首页显示不可关闭的更新横幅并可前往更新', (tester) async {
    final opened = <Uri>[];
    await _mount(tester, _GateBackend(), opened);
    expect(find.byKey(const ValueKey('home-update-required')), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '前往更新'));
    await tester.pumpAndSettle();
    expect(opened, [_updateUrl]);
    expect(find.byKey(const ValueKey('home-update-required')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('自动加载被门控拒绝不弹窗，主动重试才提示更新', (tester) async {
    final opened = <Uri>[];
    await _mount(tester, _GateBackend(), opened);
    expect(find.byKey(const ValueKey('update-required-dialog')), findsNothing);

    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    await shell.onRetryFeature(FeatureId.grades);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('update-required-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-required-dialog')), findsNothing);
    expect(opened, isEmpty);

    await shell.onRetryFeature(FeatureId.grades);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('update-required-dialog')),
        matching: find.widgetWithText(FilledButton, '前往更新'),
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, [_updateUrl]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('两种级别公告依次弹窗并在确认后记为已读', (tester) async {
    final backend = _GateBackend(gate: false)
      ..announcements = [
        _announcement('popup-1', AppAnnouncementLevel.popup),
        _announcement('banner-1', AppAnnouncementLevel.banner),
      ];
    final opened = <Uri>[];
    await _mount(tester, backend, opened);
    final dialog = find.byKey(const ValueKey('announcement-dialog-popup-1'));
    expect(dialog, findsOneWidget);

    // 打开链接不等于确认，公告仍然保留。
    await tester.tap(find.descendant(of: dialog, matching: find.text('查看详情')));
    await tester.pumpAndSettle();
    expect(opened, [_detailUrl]);
    expect(backend.read, isEmpty);

    await tester.tap(find.descendant(of: dialog, matching: find.text('知道了')));
    await tester.pumpAndSettle();
    expect(backend.read, ['popup-1']);
    expect(dialog, findsNothing);

    final banner = find.byKey(const ValueKey('announcement-dialog-banner-1'));
    expect(banner, findsOneWidget);
    await tester.tap(find.descendant(of: banner, matching: find.text('知道了')));
    await tester.pumpAndSettle();
    expect(backend.read, ['popup-1', 'banner-1']);
    expect(banner, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('新版本先弹窗，关闭后依次显示公告且一小时内重启不重复提示', (tester) async {
    final backend = _GateBackend(
      gate: false,
      available: true,
    )..announcements = [_announcement('banner-1', AppAnnouncementLevel.banner)];
    final opened = <Uri>[];
    await _mount(tester, backend, opened);
    expect(find.text('新版本 2.0.0+20'), findsOneWidget);
    expect(find.text('合成更新说明'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('announcement-dialog-banner-1')),
      findsNothing,
    );
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(
      await backend.preferences.read('flutter.ubaa.update_reminder'),
      startsWith('2.0.0+20\n'),
    );
    expect(
      find.byKey(const ValueKey('announcement-dialog-banner-1')),
      findsOneWidget,
    );
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, backend, opened);
    expect(find.text('新版本 2.0.0+20'), findsNothing);
    expect(backend.read, ['banner-1']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('新版本弹窗可以前往下载且一小时内再次启动不重复弹出', (tester) async {
    final backend = _GateBackend(gate: false, available: true);
    final opened = <Uri>[];
    await _mount(tester, backend, opened);
    await tester.tap(find.widgetWithText(FilledButton, '前往更新'));
    await tester.pumpAndSettle();
    expect(opened, [_updateUrl]);
    expect(
      await backend.preferences.read('flutter.ubaa.update_reminder'),
      startsWith('2.0.0+20\n'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, backend, opened);
    expect(find.text('新版本 2.0.0+20'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('关闭旧版本提示后仍会提示后续新版本', (tester) async {
    final backend = _GateBackend(gate: false, available: true);
    final opened = <Uri>[];
    await _mount(tester, backend, opened);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    backend.latestVersion = '2.0.1+21';
    await _mount(tester, backend, opened);
    expect(find.text('新版本 2.0.1+21'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('浏览器未能打开时提示，不把公告当作已确认', (tester) async {
    final backend = _GateBackend(
      gate: false,
    )..announcements = [_announcement('banner-2', AppAnnouncementLevel.banner)];
    await tester.pumpWidget(
      UbaaAppHost(
        preferenceValues: acceptedPrivacyPreferences(),
        backend: backend,
        urlOpener: (_) async => false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('未能打开浏览器，请稍后重试'), findsOneWidget);
    expect(backend.read, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _mount(
  WidgetTester tester,
  _GateBackend backend,
  List<Uri> opened,
) async {
  await tester.pumpWidget(
    UbaaAppHost(
      backend: backend,
      preferenceValues: backend.preferences,
      urlOpener: (url) async {
        opened.add(url);
        return true;
      },
    ),
  );
  await tester.pumpAndSettle();
}

/// 已同意且取得启动配置的合成后端；学校读取一律被门控拒绝。
class _GateBackend extends DemoBackend implements AppBootstrapBackend {
  _GateBackend({this.gate = true, this.available = false});
  final bool available;
  final preferences = acceptedPrivacyPreferences();
  String latestVersion = '2.0.0+20';
  final dismissed = <String>[];
  final bool gate;
  var announcements = <AppAnnouncement>[];
  final read = <String>[];

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async => gate
      ? throw const BackendException(UbaaErrorCode.updateRequired)
      : const FeatureResult.empty();

  AppServiceView get _view => AppServiceView(
    available: true,
    telemetryAllowed: true,
    consent: AppServiceConsent.agreed,
    policyVersion: bundledPrivacyPolicy.version,
    agreedPolicyVersion: bundledPrivacyPolicy.version,
    telemetryEnabled: true,
    canErase: true,
    erase: AppServiceEraseStatus.idle,
    update: AppUpdateView(
      status: gate
          ? AppUpdateStatus.updateRequired
          : available
          ? AppUpdateStatus.updateAvailable
          : AppUpdateStatus.upToDate,
      latestVersion: latestVersion,
      minSupportedVersion: gate ? '2.0.0' : null,
      url: _updateUrl,
      releaseNotes: '合成更新说明',
      gateActive: gate,
      availableDismissed: dismissed.contains(latestVersion),
    ),
    announcements: [
      for (final item in announcements)
        if (!read.contains(item.id)) item,
    ],
  );

  @override
  Future<AppServiceView> appServiceState() async => _view;
  @override
  Future<void> refreshAppBootstrap({required bool force}) async {}
  @override
  Future<AppServiceView> markAppAnnouncementRead(String id) async {
    read.add(id);
    return _view;
  }

  @override
  Future<AppServiceView> dismissAppUpdateAvailable(String latestVersion) async {
    dismissed.add(latestVersion);
    return _view;
  }

  @override
  Future<AppServiceView> agreeAppService() async => _view;
  @override
  Future<AppServiceView> enterBasicAppService() async => _view;
  @override
  Future<AppServiceView> setAppServiceTelemetry(bool enabled) async => _view;
  @override
  Future<AppServiceEraseOutcome> eraseAppService() async =>
      AppServiceEraseOutcome.succeeded;
  @override
  Future<void> uploadAppService({required bool force}) async {}
  @override
  Future<void> recordAppService(TelemetryRecord record) async {}
}
