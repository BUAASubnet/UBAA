import 'dart:async';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:ubaa_app/app_service_host.dart';
import 'package:ubaa_app/command.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_platform/shared_accounts.dart';

/// Linux AOT 入口与 GUI 使用同一服务，不创建 Engine 或 GApplication。
Future<void> main(List<String> arguments) async {
  final elapsed = Stopwatch()..start();
  Timer? force;
  final startupDeadline = Timer(const Duration(seconds: 122), () => exit(5));
  try {
    final executable = File(Platform.resolvedExecutable).parent.path;
    final io = ConsoleCommandIO();
    final runtime = CommandRuntime(
      io: io,
      openClient: ({required configDir}) => openConfiguredCommandClient(
        configDirectory: configDir,
        release: const bool.fromEnvironment(
          'UBAA_COMMAND_RELEASE',
          defaultValue: true,
        ),
        readVersion: linuxCommandAppVersion,
      ),
      uploadAppService: (context) => uploadConfiguredCommandAppService(
        resolveDirectory: () async => switch (context.directory) {
          final configured? => Directory(configured).absolute.path,
          null => linuxCommandDirectory(),
        },
        budget: context.budget,
        account: context.account,
        release: const bool.fromEnvironment(
          'UBAA_COMMAND_RELEASE',
          defaultValue: true,
        ),
        readVersion: linuxCommandAppVersion,
      ),
      openMaterials: (configured) async {
        final directory = configured == null
            ? await linuxCommandDirectory()
            : Directory(configured).absolute.path;
        final materials = SecureMaterialStore(
          transport: LinuxSecretServiceTransport(),
          coordinator: MaterialCoordinator(
            directory: MaterialCoordinator.desktopDirectory(),
          ),
        );
        await materials.probe();
        return CommandMaterials(directory: directory, materials: materials);
      },
    );
    runtime.stopped.then((_) {
      io.restoreTerminal();
      force ??= Timer(
        const Duration(seconds: 2),
        () => exit(runtime.stoppedExitCode),
      );
    });
    void cancel() {
      io.restoreTerminal();
      runtime.cancel();
      force ??= Timer(const Duration(seconds: 2), () => exit(7));
    }

    final interrupts = ProcessSignal.sigint.watch().listen((_) => cancel());
    final terminations = ProcessSignal.sigterm.watch().listen((_) => cancel());
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        '$executable/lib/libubaa_flutter_bridge.so',
      ),
    );
    startupDeadline.cancel();
    final code = await runtime.run([
      'ubaa-cli',
      ...arguments,
    ], budget: const Duration(minutes: 2) - elapsed.elapsed);
    io.restoreTerminal();
    force?.cancel();
    await interrupts.cancel();
    await terminations.cancel();
    startupDeadline.cancel();
    exit(code);
  } on Object {
    startupDeadline.cancel();
    stderr.writeln("命令运行资源不可用");
    exit(7);
  }
}

final class ConsoleCommandIO implements CommandIO {
  bool? _originalEcho;
  void restoreTerminal() {
    final echo = _originalEcho;
    if (echo == null) return;
    _originalEcho = null;
    stdin.echoMode = echo;
  }

  @override
  Future<void> configure({required bool local}) async {}
  final StreamIterator<List<int>> _input = StreamIterator(stdin);
  final List<int> _pending = [];
  @override
  Future<List<int>?> readLine({required bool secret}) async {
    bool? oldEcho;
    if (secret) {
      try {
        oldEcho = stdin.echoMode;
      } on StdinException catch (error) {
        // ENOTTY 表示输入来自管道或文件。
        if (error.osError?.errorCode != 25) rethrow;
      }
      if (oldEcho != null) {
        _originalEcho = oldEcho;
        stdin.echoMode = false;
      }
    }
    try {
      while (true) {
        final newline = _pending.indexOf(10);
        if (newline >= 0) {
          final result = _pending.sublist(0, newline + 1);
          _pending.removeRange(0, newline + 1);
          return result;
        }
        if (!await _input.moveNext()) {
          if (_pending.isEmpty) return null;
          final result = List<int>.of(_pending);
          _pending.clear();
          return result;
        }
        _pending.addAll(_input.current);
        if (_pending.length > 1048576)
          throw const FileSystemException('命令输入过大');
      }
    } finally {
      if (secret && oldEcho != null) {
        restoreTerminal();
        stderr.writeln();
      }
    }
  }

  @override
  Future<List<int>> readBody() async {
    final bytes = List<int>.of(_pending);
    _pending.clear();
    while (await _input.moveNext()) {
      bytes.addAll(_input.current);
      if (bytes.length > 1048576) throw const FileSystemException('命令输入过大');
    }
    return bytes;
  }

  @override
  Future<void> writeStdout(List<int> bytes) async {
    stdout.add(bytes);
    await stdout.flush();
  }

  @override
  Future<void> writeStderr(List<int> bytes) async {
    stderr.add(bytes);
    await stderr.flush();
  }
}
