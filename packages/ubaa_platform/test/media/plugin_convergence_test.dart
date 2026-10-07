import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('macOS 选图也复用已注册文件插件，不再需要照片专属原生通道', () async {
    final capabilities = await createDefaultPhotoCapabilities(
      targetPlatform: TargetPlatform.macOS,
    );
    expect(capabilities.picker, isA<DesktopFilePhotoPicker>());
  });
}
