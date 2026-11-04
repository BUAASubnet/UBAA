import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:ubaa_app/command.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

const _channel = MethodChannel('cn.edu.ubaa/command');

/// 无窗口 Engine 使用窄通道交付终端 I/O，不装配页面或 Controller。
Future<void> runEngineCommand(
  List<String> arguments, {
  Future<CommandMaterials> Function(String? configured)? openMaterials,
}) async {
  _CommandBinding();
  try {
    await RustLib.init();
    final runtime = CommandRuntime(
      io: _EngineIO(),
      openMaterials:
          openMaterials ??
          (configured) async {
            await initializePrivateDirectory();
            final materials = SecureMaterialStore();
            await materials.probe();
            return CommandMaterials(
              directory: configured == null
                  ? defaultConfigDirectory()
                  : Directory(configured).absolute.path,
              materials: materials,
            );
          },
    );
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'cancel') runtime.cancel();
      if (call.method == 'deadline') runtime.expire();
    });
    final config = await _channel.invokeMapMethod<String, Object?>('config');
    final remaining = config?['remainingMillis'] as int? ?? 0;
    final code = await runtime.run(
      arguments,
      budget: Duration(milliseconds: remaining),
    );
    await _channel.invokeMethod<void>('complete', code);
  } on Object {
    await _channel.invokeMethod<void>('complete', 7);
  }
}

final class _CommandBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {}

final class _EngineIO implements CommandIO {
  @override
  Future<void> configure({required bool local}) =>
      _channel.invokeMethod<void>('configure', local);
  @override
  Future<List<int>?> readLine({required bool secret}) =>
      _channel.invokeMethod<Uint8List>('readLine', secret);
  @override
  Future<List<int>> readBody() async =>
      (await _channel.invokeMethod<Uint8List>('readBody')) ?? <int>[];
  @override
  Future<void> writeStdout(List<int> bytes) =>
      _channel.invokeMethod<void>('stdout', Uint8List.fromList(bytes));
  @override
  Future<void> writeStderr(List<int> bytes) =>
      _channel.invokeMethod<void>('stderr', Uint8List.fromList(bytes));
}
