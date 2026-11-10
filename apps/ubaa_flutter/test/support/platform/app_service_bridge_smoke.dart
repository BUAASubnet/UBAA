import 'dart:async';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/app_service_host.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  const directory = String.fromEnvironment('UBAA_APP_SERVICE_TEST_STATE');
  const library = String.fromEnvironment('UBAA_APP_SERVICE_TEST_LIBRARY');
  const reopened = bool.fromEnvironment('UBAA_APP_SERVICE_TEST_REOPEN');
  test(reopened ? '重启后恢复删除、门控和公告已读状态' : '同意后刷新配置、标记公告已读并真实上传', () async {
    if (directory.isEmpty || library.isEmpty) {
      fail('请从 scripts/tests/app_service/bridge_e2e.py 执行本地联调');
    }
    await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    Future<BridgeAppService> open(BridgeAppServiceSurface surface) async =>
        (await openConfiguredAppService(
          configDirectory: directory,
          surface: surface,
          release: false,
          readVersion: () async => '2.1.0-rc.1+15',
          budget: const Duration(seconds: 15),
        ))!;
    final gui = AppController(
      backend: await BridgeBackend.open(
        directory,
        appService: await open(BridgeAppServiceSurface.gui),
      ),
    );
    final command = await open(BridgeAppServiceSurface.command);
    final bootstrapArrived = Completer<void>();
    void observeBootstrap() {
      if (gui.appUpdate != null && !bootstrapArrived.isCompleted) {
        bootstrapArrived.complete();
      }
    }

    gui.addListener(observeBootstrap);
    try {
      if (reopened) {
        expect(
          (await gui.refreshAppService()).erase,
          AppServiceEraseStatus.pending,
        );
        expect(gui.appService.telemetryEnabled, isFalse);
        expect(gui.appUpdate?.gateActive, isTrue);
        expect(gui.pendingAnnouncements, isEmpty);
        expect((await command.state()).erasePending, isTrue);
        await gui.uploadAppService(force: true);
        expect(gui.appService.erase, AppServiceEraseStatus.idle);
        expect((await command.state()).erasePending, isFalse);
        return;
      }

      expect((await gui.refreshAppService()).needsConsentPrompt, isTrue);
      expect((await command.state()).consent, BridgeAppServiceConsent.unasked);
      expect(
        (await gui.agreePrivacyPolicy()).consent,
        AppServiceConsent.agreed,
      );
      expect((await command.state()).consent, BridgeAppServiceConsent.agreed);
      await gui.recordAppStarted();
      await gui.uploadAppService(force: true);
      await bootstrapArrived.future.timeout(const Duration(seconds: 10));
      expect(gui.appUpdate?.status, AppUpdateStatus.updateRequired);
      expect(gui.appUpdate?.latestVersion, '2.2.0+17');
      expect(gui.appUpdate?.gateActive, isTrue);
      final notice = gui.pendingAnnouncements.single;
      expect(notice.level, AppAnnouncementLevel.popup);
      expect(notice.body, '合成公告正文');
      final commandState = await command.refreshBootstrap(force: true);
      expect(commandState.update?.status, BridgeAppUpdateStatus.updateRequired);
      expect(commandState.update?.gateActive, isTrue);
      expect(commandState.announcements.single.id, notice.id);
      // 隔离目录从未登录。即使门控失效，无本机会话的状态检查也不会访问学校。
      final schoolClient = await BridgeClient.openWithAppService(
        configDir: directory,
        appService: command,
      );
      try {
        await expectLater(
          schoolClient.authStatus(),
          throwsA(
            isA<BridgeError>()
                .having(
                  (error) => error.code,
                  '错误码',
                  BridgeErrorCode.updateRequired,
                )
                .having((error) => error.retryable, '可重试', isFalse),
          ),
        );
      } finally {
        await schoolClient.dispose();
      }
      await gui.markAnnouncementRead(notice.id);
      expect(gui.pendingAnnouncements, isEmpty);
      expect((await command.state()).announcements, isEmpty);
      expect(
        (await gui.setProductTelemetryEnabled(false)).telemetryEnabled,
        isFalse,
      );
      expect((await command.state()).telemetryEnabled, isFalse);
      expect(
        await command.enqueueCounter(
          event: BridgeTelemetryCounter.featureLoaded,
          feature: BridgeTelemetryFeature.schedule,
          route: BridgeTelemetryRoute.none,
          result: BridgeTelemetryResult.success,
        ),
        isFalse,
      );
      expect((await command.upload(force: false)).batchesSent, 0);
      expect(
        await gui.eraseUploadedTelemetry(),
        AppServiceEraseOutcome.pending,
      );
      expect(gui.appService.erase, AppServiceEraseStatus.pending);
    } finally {
      gui.removeListener(observeBootstrap);
      gui.dispose();
      command.dispose();
    }
  });
}
