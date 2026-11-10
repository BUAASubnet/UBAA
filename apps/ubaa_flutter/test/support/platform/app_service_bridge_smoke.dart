import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/app_service_host.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  final directory = Platform.environment['UBAA_CONFIG_DIR'];
  const library = String.fromEnvironment('UBAA_APP_SERVICE_TEST_LIBRARY');
  const reopened = bool.fromEnvironment('UBAA_APP_SERVICE_TEST_REOPEN');
  test(reopened ? '基础模式重启后只重试删除' : '刷新门控和公告、上传并清理待重试数据', () async {
    if (directory == null || directory.isEmpty || library.isEmpty) {
      fail('请从 just app-service-e2e 执行本地联调');
    }
    await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    Future<String> readVersion() async => '2.1.0-rc.1+15';
    final backend = await createProductionBackend(
      openAppService: (configDirectory) => openConfiguredAppService(
        configDirectory: configDirectory,
        surface: BridgeAppServiceSurface.gui,
        release: false,
        readVersion: readVersion,
      ),
    );
    expect(backend, isA<BridgeBackend>());
    final gui = AppController(backend: backend);
    final command = (await openConfiguredAppService(
      configDirectory: directory,
      surface: BridgeAppServiceSurface.command,
      release: false,
      readVersion: readVersion,
    ))!;
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
        expect(gui.appService.consent, AppServiceConsent.basic);
        expect(gui.appUpdate, isNull);
        expect(gui.pendingAnnouncements, isEmpty);
        expect((await command.state()).erasePending, isTrue);
        await Future.wait([
          gui.uploadAppService(force: true),
          uploadConfiguredCommandAppService(
            resolveDirectory: () async => directory,
            budget: const Duration(seconds: 2),
            release: false,
            readVersion: readVersion,
          ),
        ]);
        expect(gui.appService.erase, AppServiceEraseStatus.idle);
        expect((await command.state()).erasePending, isFalse);
        // 只恢复 SQLite 中的同意，读取上次启动配置，不触发控制器重新拉取。
        await (backend as AppServiceBackend).agreeAppService();
        final restored = await command.state();
        expect(restored.update?.gateActive, isTrue);
        expect(restored.announcements, isEmpty);
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
      final schoolClient = await openConfiguredCommandClient(
        configDirectory: directory,
        release: false,
        readVersion: readVersion,
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
      await gui.recordAppCrash(StateError('合成错误消息'), null);
      await gui.uploadAppService(force: true);
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
        (await gui.setProductTelemetryEnabled(true)).telemetryEnabled,
        isTrue,
      );
      await gui.uploadAppService(force: true);
      await gui.setProductTelemetryEnabled(false);
      expect(
        (await gui.withdrawPrivacyConsent()).consent,
        AppServiceConsent.basic,
      );
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
