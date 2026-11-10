import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';

void main() {
  test('界面从共享持久状态显示选择、关闭和待重试删除', () async {
    final store = _Store();
    final gui = AppController(backend: _Backend(store));
    final command = _Backend(store);
    addTearDown(gui.dispose);
    final notifications = <AppServiceView>[];
    gui.addListener(() => notifications.add(gui.appService));

    await gui.refreshAppService();
    expect(gui.appService.needsConsentPrompt, isTrue);
    store.rejectAgreement = true;
    expect((await gui.agreePrivacyPolicy()).consent, AppServiceConsent.unasked);
    store.rejectAgreement = false;
    expect((await gui.agreePrivacyPolicy()).consent, AppServiceConsent.agreed);

    await command.setAppServiceTelemetry(false);
    await gui.refreshAppService();
    expect(gui.appService.telemetryEnabled, isFalse);

    final pending = gui.eraseUploadedTelemetry();
    await store.eraseStarted.future;
    expect(gui.appService.erase, AppServiceEraseStatus.running);
    expect(
      (await command.appServiceState()).erase,
      AppServiceEraseStatus.pending,
    );
    store.eraseReply.complete();
    expect(await pending, AppServiceEraseOutcome.pending);
    expect(gui.appService.erase, AppServiceEraseStatus.pending);
    expect(
      notifications.map((state) => state.erase),
      contains(AppServiceEraseStatus.running),
    );

    await gui.withdrawPrivacyConsent();
    expect(gui.appService.consent, AppServiceConsent.basic);
    expect(gui.appService.canErase, isTrue);
  });

  test('更新和公告投影保留版本，按本机时间筛选，读取与忽略通知监听者', () async {
    final store = _Store()..consent = AppServiceConsent.agreed;
    final gui = AppController(backend: _Backend(store));
    addTearDown(gui.dispose);
    await gui.refreshAppService();
    expect(gui.appUpdate, isNull);
    expect(gui.pendingAnnouncements, isEmpty);

    var notifications = 0;
    gui.addListener(() => notifications++);
    await gui.refreshAppBootstrap(force: true);
    expect(store.bootstrapForces, [true]);
    expect(gui.appUpdate?.latestVersion, '2.3.0+15');
    expect(gui.appUpdate?.availableDismissed, isFalse);
    expect(gui.pendingAnnouncements.map((item) => item.id), [
      'first',
      'second',
    ]);

    await gui.markAnnouncementRead('first');
    await gui.dismissUpdateAvailable();
    expect(gui.pendingAnnouncements.map((item) => item.id), ['second']);
    expect(store.dismissed, '2.3.0+15');
    expect(gui.appUpdate?.availableDismissed, isTrue);
    expect(notifications, 3);

    await gui.withdrawPrivacyConsent();
    expect(gui.appUpdate, isNull);
    expect(gui.pendingAnnouncements, isEmpty);
    await gui.agreePrivacyPolicy();
    await Future<void>.delayed(Duration.zero);
    expect(store.bootstrapForces, [true, true]);
    expect(gui.appUpdate?.availableDismissed, isTrue);
  });

  test('自动恢复和自动刷新不弹出提示，主动重试和下拉各发出一次信号', () async {
    final backend = _Backend(_Store());
    final gui = AppController(backend: backend);
    addTearDown(gui.dispose);
    var prompts = 0;
    final subscription = gui.updatePromptRequests.listen((_) => prompts++);
    addTearDown(subscription.cancel);
    await gui.initialize();
    gui.setUsername('synthetic-user');
    gui.setPassword('synthetic-password');
    await gui.submitLogin();
    await gui.refreshHome();
    backend.gated = true;
    backend.gatedAuth = true;
    await gui.resumeSession();
    expect(gui.error?.code, UbaaErrorCode.updateRequired);
    backend.gatedAuth = false;
    await gui.resumeSession();
    await Future<void>.delayed(Duration.zero);
    expect(backend.deniedReads, greaterThan(0));
    expect(prompts, 0);
    await gui.retryFeature(FeatureId.schedule);
    await Future<void>.delayed(Duration.zero);
    expect(prompts, 1);
    await gui.refreshHomePage();
    await Future<void>.delayed(Duration.zero);
    expect(prompts, 2);
  });

  test('已知门控时主动登录保留会话，撤回后可重新提交', () async {
    final store = _Store()
      ..consent = AppServiceConsent.agreed
      ..gateActive = true;
    final backend = _Backend(store);
    final gui = AppController(backend: backend);
    addTearDown(gui.dispose);
    await gui.initialize();
    await gui.refreshAppBootstrap(force: true);
    gui.setUsername('synthetic-user');
    gui.setPassword('synthetic-password');
    final prompt = gui.updatePromptRequests.first;
    await gui.submitLogin();
    await prompt;
    expect(gui.error?.code, UbaaErrorCode.updateRequired);
    expect(gui.error?.retryable, isFalse);
    expect(backend.loginCalls, 0);
    await gui.withdrawPrivacyConsent();
    await gui.submitLogin();
    expect(backend.loginCalls, 1);
    expect(gui.phase, AppPhase.home);
  });

  test('撤回同意不等待在途启动配置，迟到的刷新不会重开界面', () async {
    final store = _Store()..consent = AppServiceConsent.agreed;
    final gui = AppController(backend: _Backend(store));
    addTearDown(gui.dispose);
    await gui.refreshAppBootstrap(force: true);
    expect(gui.appUpdate, isNotNull);
    final reply = store.bootstrapReply = Completer<void>();
    final refresh = gui.refreshAppBootstrap();
    expect(
      (await gui.withdrawPrivacyConsent()).consent,
      AppServiceConsent.basic,
    );
    expect(gui.appUpdate, isNull);
    reply.complete();
    await refresh;
    expect(gui.appUpdate, isNull);
    expect(gui.pendingAnnouncements, isEmpty);
  });
}

class _Store {
  bool rejectAgreement = false;
  bool enabled = false;
  var consent = AppServiceConsent.unasked;
  bool installed = false;
  var erase = AppServiceEraseStatus.idle;
  final eraseStarted = Completer<void>();
  final eraseReply = Completer<void>();
  final bootstrapForces = <bool>[];
  final read = <String>{};
  String? dismissed;
  bool gateActive = false;
  Completer<void>? bootstrapReply;
}

class _Backend extends DemoBackend implements AppBootstrapBackend {
  _Backend(this.store);
  final _Store store;
  bool gated = false;
  bool gatedAuth = false;
  int loginCalls = 0;
  int deniedReads = 0;

  @override
  Future<AuthStatus> authStatus() async {
    if (gatedAuth) throw const BackendException(UbaaErrorCode.updateRequired);
    return super.authStatus();
  }

  @override
  Future<void> login(LoginInput input) {
    loginCalls++;
    return super.login(input);
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (gated) {
      deniedReads++;
      throw const BackendException(UbaaErrorCode.updateRequired);
    }
    return super.loadFeature(feature);
  }

  AppAnnouncement _announcement(String id, int start, int? end) =>
      AppAnnouncement(
        id: id,
        level: AppAnnouncementLevel.popup,
        title: '公告',
        body: '正文',
        startsAt: DateTime.now().add(Duration(days: start)),
        endsAt: end == null ? null : DateTime.now().add(Duration(days: end)),
      );

  late final _announcements = [
    _announcement('first', -1, 1),
    _announcement('expired', -2, -1),
    _announcement('future', 1, 2),
    _announcement('second', -1, null),
  ];

  @override
  Future<AppServiceView> appServiceState() async => AppServiceView(
    available: true,
    telemetryAllowed: true,
    consent: store.consent,
    policyVersion: 1,
    agreedPolicyVersion: store.consent == AppServiceConsent.agreed ? 1 : null,
    telemetryEnabled: store.enabled,
    canErase: store.installed,
    erase: store.erase,
    update: store.bootstrapForces.isEmpty
        ? null
        : AppUpdateView(
            status: store.gateActive
                ? AppUpdateStatus.updateRequired
                : AppUpdateStatus.updateAvailable,
            latestVersion: '2.3.0+15',
            gateActive: store.gateActive,
            availableDismissed: store.dismissed == '2.3.0+15',
          ),
    announcements: store.bootstrapForces.isEmpty
        ? const []
        : _announcements
              .where((item) => !store.read.contains(item.id))
              .toList(),
  );

  @override
  Future<void> refreshAppBootstrap({required bool force}) async {
    store.bootstrapForces.add(force);
    await store.bootstrapReply?.future;
  }

  @override
  Future<AppServiceView> markAppAnnouncementRead(String id) {
    store.read.add(id);
    return appServiceState();
  }

  @override
  Future<AppServiceView> dismissAppUpdateAvailable(String latestVersion) {
    store.dismissed = latestVersion;
    return appServiceState();
  }

  @override
  Future<AppServiceView> agreeAppService() async {
    if (store.rejectAgreement) throw StateError('合成持久化失败');
    store.consent = AppServiceConsent.agreed;
    store.enabled = true;
    store.installed = true;
    return appServiceState();
  }

  @override
  Future<AppServiceView> enterBasicAppService() async {
    store.consent = AppServiceConsent.basic;
    return appServiceState();
  }

  @override
  Future<AppServiceView> setAppServiceTelemetry(bool enabled) async {
    store.enabled = enabled;
    return appServiceState();
  }

  @override
  Future<AppServiceEraseOutcome> eraseAppService() async {
    store.erase = AppServiceEraseStatus.pending;
    store.eraseStarted.complete();
    await store.eraseReply.future;
    return AppServiceEraseOutcome.pending;
  }

  @override
  Future<void> uploadAppService({required bool force}) async {}

  @override
  Future<void> recordAppService(TelemetryRecord record) async {}
}
