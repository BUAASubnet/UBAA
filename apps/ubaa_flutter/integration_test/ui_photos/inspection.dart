import 'package:flutter/material.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../ui_sports/write_backend.dart';

/// 系统照片选择器保持真实，学校业务明确留在内存。
Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // 检查进程存活期间保留原生语义树，便于独立电脑操作。
  binding.ensureSemantics();
  final capabilities = await createDefaultPlatformCapabilities();
  runApp(
    UbaaFlutterApp(
      backend: SportsWriteBackend('success'),
      credentialVault: MemoryCredentialVault(),
      photoPicker: capabilities.photoPicker,
      permissionGateway: capabilities.permissionGateway,
      initialTab: 2,
    ),
  );
}
