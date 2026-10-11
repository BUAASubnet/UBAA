import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_app/ubaa_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android正式Core可从原生私有目录初始化', (tester) async {
    await RustLib.init();
    await initializePrivateDirectory();
    final BridgeBackend backend;
    try {
      backend = await BridgeBackend.open(defaultConfigDirectory());
    } on BridgeError catch (error) {
      fail('Core初始化失败：${error.code.name}/${error.kind.name} ${error.message}');
    }
    try {
      expect(await backend.authStatus(), AuthStatus.signedOut);
      if (const bool.fromEnvironment('UBAA_VERIFY_WEBVPN')) {
        // 显式live入口只获取登录准备页，不传账号密码，不提交登录或业务写入。
        await backend.setDefaultRoutePolicy(RoutePolicy.webvpn);
        final prepared = await backend.client.prepareLogin();
        final webvpn = prepared.routes.singleWhere(
          (r) => r.route == BridgeConnectionMode.webVpn,
        );
        expect(webvpn.error, isNull);
      }
    } finally {
      await backend.dispose();
    }
  });
  testWidgets('Android真实通道完成加密发布、退出清理并拒绝迟到结果', (tester) async {
    const gateway = AndroidScheduleWidgetGateway();
    final snapshot = ScheduleWidgetSnapshot(
      owner: 'synthetic-channel',
      semesters: [],
    );
    final scope = await gateway.begin(snapshot.owner);
    try {
      await gateway.publish(scope, snapshot);
      await gateway.begin(null);
      await expectLater(
        gateway.publish(scope, snapshot),
        throwsA(isA<PlatformException>()),
      );
    } finally {
      await gateway.begin(null);
    }
  });
}
