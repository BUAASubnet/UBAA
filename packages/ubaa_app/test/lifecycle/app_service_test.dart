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
}

class _Store {
  bool rejectAgreement = false;
  bool enabled = false;
  var consent = AppServiceConsent.unasked;
  bool installed = false;
  var erase = AppServiceEraseStatus.idle;
  final eraseStarted = Completer<void>();
  final eraseReply = Completer<void>();
}

class _Backend extends DemoBackend implements AppServiceBackend {
  _Backend(this.store);
  final _Store store;

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
  );

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
