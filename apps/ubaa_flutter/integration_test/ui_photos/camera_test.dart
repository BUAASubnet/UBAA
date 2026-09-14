import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../ui_sports/write_backend.dart';

/// 仅验证原生宿主中的拍照UI流程，不冒充设备相机实操。
class _CameraFixture implements PlatformPhotoPicker, PlatformPhotoCapture {
  @override
  bool get isAvailable => true;
  @override
  bool get canCapturePhoto => true;
  bool cancelled = false, failed = false;
  @override
  Future<YgdkPhotoInput?> pickPhoto() async => _photo('selected.png');
  @override
  Future<YgdkPhotoInput?> capturePhoto() async {
    if (failed) throw StateError('合成设备错误，不应显示');
    return cancelled ? null : _photo('camera.png');
  }

  YgdkPhotoInput _photo(String name) => YgdkPhotoInput(
    bytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAO0lEQVR4nO3RQREAMAjEwKMW66K2MFoJ4cMvK+CYCXVfZ9NZXY8HBvwBMhEyETIRMhEyETIRMhEyUcgHOh4BoA8A/HAAAAAASUVORK5CYII=',
    ),
    fileName: name,
    mimeType: 'image/png',
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    testWidgets('原生宿主可选拍照与选图共享照片状态 ${brightness.name}', (tester) async {
      final backend = SportsWriteBackend('success');
      final picker = _CameraFixture();
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        UbaaFlutterApp(
          backend: backend,
          credentialVault: MemoryCredentialVault(),
          photoPicker: picker,
          permissionGateway: MemoryPermissionGateway(
            initial: {
              PlatformPermission.photos: PlatformPermissionStatus.granted,
              PlatformPermission.camera: PlatformPermissionStatus.granted,
            },
          ),
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

      Future<void> shot(String scene) async {
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final size = tester.view.physicalSize;
        final ratio = tester.view.devicePixelRatio;
        final name = '${brightness.name}-camera-$scene';
        final records =
            (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
                  'uiEvidence',
                  () => <Object?>[],
                )
                as List;
        records.add({
          'name': name,
          'steps': '可选拍照入口、取消/失败保图、成功替换及退出释放；相机与业务均显式内存',
          'backend': 'synthetic-sports-synthetic-camera',
          'systemCameraVerified': false,
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
          await binding.takeScreenshot(name);
        } else {
          debugPrint('原生合成拍照UI检查点：$name');
        }
      }

      await tap(find.widgetWithText(Card, '阳光打卡'));
      await tap(find.byTooltip('新增打卡'));
      await tester.ensureVisible(find.text('拍摄照片'));
      await shot('entry');
      await tap(find.text('选择照片'));
      expect(find.text('已选择照片：selected.png'), findsOneWidget);
      picker.cancelled = true;
      await tap(find.text('拍摄照片'));
      expect(find.text('已选择照片：selected.png'), findsOneWidget);
      await shot('cancel-retains');
      picker.failed = true;
      await tap(find.text('拍摄照片'));
      expect(find.text('已选择照片：selected.png'), findsOneWidget);
      expect(find.textContaining('无法读取照片'), findsOneWidget);
      expect(find.textContaining('合成设备错误'), findsNothing);
      await shot('error-retains');
      picker.failed = picker.cancelled = false;
      await tap(find.text('拍摄照片'));
      expect(find.text('已选择照片：camera.png'), findsOneWidget);
      expect(find.textContaining('无法读取照片'), findsNothing);
      await shot('captured');
      await tap(find.text('取消'));
      await tap(find.byTooltip('新增打卡'));
      await tester.ensureVisible(find.text('拍摄照片'));
      expect(find.byKey(const ValueKey('ygdk-photo-preview')), findsNothing);
      await shot('reentered-empty');
      await tap(find.text('取消'));
      expect(backend.prepared, isEmpty);
      expect(backend.commitCalls, 0);
    });
  }
}
