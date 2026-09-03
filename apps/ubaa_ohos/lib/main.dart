import 'package:flutter/widgets.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 保留 HarmonyOS 宿主的既有公开名称。
typedef UbaaOhosApp = UbaaAppHost;

Future<void> main() => bootstrapUbaaOhosApp();

/// 按固定顺序完成 HarmonyOS 宿主装配。
///
/// 可注入的边界只用于验证入口 wiring；生产调用不传参数，始终使用真实平台实现。
Future<void> bootstrapUbaaOhosApp({
  void Function()? ensureInitialized,
  Future<void> Function()? initializeRust,
  String Function()? debugHello,
  Future<PlatformCapabilities> Function()? createCapabilities,
  void Function(Widget)? runApplication,
}) => bootstrapUbaaHost(
  ensureFlutterInitialized:
      ensureInitialized ?? WidgetsFlutterBinding.ensureInitialized,
  initializeSdk: initializeRust ?? RustLib.init,
  debugHello: debugHello ?? bridgeHello,
  createCapabilities: createCapabilities ?? createDefaultPlatformCapabilities,
  runApplication: runApplication ?? runApp,
);
