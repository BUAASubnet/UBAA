import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../ui_sports/write_backend.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('生产原生照片选择能力已注册', (tester) async {
    final capabilities = await createDefaultPlatformCapabilities();
    expect(capabilities.photoPicker.isAvailable, isTrue);
    expect(
      await capabilities.permissionGateway.request(PlatformPermission.photos),
      PlatformPermissionStatus.granted,
    );
    // 仅确认系统选择器可被请求，不读取任何照片或学校业务。
  });
  for (final brightness in Brightness.values) {
    testWidgets('原生平台能力贯通独立表单 ${brightness.name}', (tester) async {
      final capabilities = await createDefaultPlatformCapabilities();
      final backend = SportsWriteBackend('success');
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        UbaaFlutterApp(
          backend: backend,
          credentialVault: MemoryCredentialVault(),
          photoPicker: capabilities.photoPicker,
          permissionGateway: capabilities.permissionGateway,
          initialTab: 2,
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> shot(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final size = tester.view.physicalSize;
        final ratio = tester.view.devicePixelRatio;
        final label = '${brightness.name}-native-photo-$name';
        final records =
            (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
                  'uiEvidence',
                  () => <Object?>[],
                )
                as List;
        records.add({
          'name': label,
          'steps': '真实平台照片探测贯通原生表单，学校业务仅内存；未选择照片或提交',
          'backend': 'synthetic-sports-real-platform',
          'platform': Platform.operatingSystem,
          'system': Platform.operatingSystemVersion,
          'logicalWidth': size.width / ratio,
          'logicalHeight': size.height / ratio,
          'devicePixelRatio': ratio,
          'viewportSource': 'native-view-unmodified',
          'dateUtc': DateTime.now().toUtc().toIso8601String(),
          'sourceSha': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
        });
        if (Platform.isIOS) {
          await binding.takeScreenshot(label);
        } else {
          debugPrint('原生照片接线检查点：$label');
        }
      }

      await tap(find.widgetWithText(Card, '阳光打卡'));
      expect(find.byTooltip('新增打卡'), findsOneWidget);
      await shot('home');
      await tap(find.byTooltip('新增打卡'));
      expect(find.widgetWithText(AppBar, '填写阳光打卡信息'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await shot('form');
      await tap(find.text('选择运动项目'));
      await shot('projects');
      await tap(find.text('关闭'));
      await tester.ensureVisible(find.text('选择照片'));
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '选择照片'))
            .onPressed,
        isNotNull,
      );
      await shot('photo-entry');
      await tap(find.text('取消'));
      expect(backend.commitCalls, 0);
    });
  }
}
