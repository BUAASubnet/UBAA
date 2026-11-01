import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ubaa_platform/shared_accounts.dart';

/// 实际 Windows 整文件传输加合成 codec；不调用 DPAPI 或默认材料目录。
WindowsFileMaterials syntheticWindowsMaterials(Directory root) =>
    WindowsFileMaterials(
      file: () async => File('${root.path}/synthetic_materials.dat'),
      codec: const SyntheticMaterialCodec(),
    );

final class SyntheticMaterialCodec implements WindowsMaterialCodec {
  const SyntheticMaterialCodec();
  @override
  Uint8List decrypt(Uint8List bytes) {
    if (bytes.isEmpty || bytes.first != 1) throw const FormatException('合成格式');
    return Uint8List.fromList(bytes.sublist(1));
  }

  @override
  Uint8List encrypt(Uint8List bytes) => Uint8List.fromList([1, ...bytes]);
}

final class _PausingMaterials implements SecureMaterialTransport {
  _PausingMaterials(this.transport);
  final SecureMaterialTransport transport;
  @override
  Future<String?> read(String key) => transport.read(key);
  @override
  Future<void> delete(String key) => transport.delete(key);
  @override
  Future<void> write(String key, String value) async {
    await transport.write(key, value);
    if (key.contains('cache-key.')) {
      stdout.writeln('MUTATION_PENDING:$pid');
      Timer.periodic(const Duration(seconds: 1), (_) {});
      await Completer<void>().future;
    }
  }
}

Future<void> main(List<String> args) async {
  final root = Directory(args[0]);
  final command = args[1];
  if (command == 'defaultDirectory') {
    stdout.writeln(MaterialCoordinator.desktopDirectory().path);
    return;
  }
  // 使用固定材料域解析器；配置目录、路径别名与可执行名称不参与锁域。
  final coordinator = MaterialCoordinator(
    directory: args.length > 3
        ? Directory(args[3])
        : Directory('${root.path}/coordination'),
    waitLimit: const Duration(milliseconds: 300),
  );
  if (command == 'hold') {
    await coordinator.run(() async {
      stdout.writeln('LOCKED:$pid');
      Timer.periodic(const Duration(seconds: 1), (_) {});
      await Completer<void>().future;
    });
    return;
  }
  final materials = SecureMaterialStore(
    transport: command == 'crash'
        ? _PausingMaterials(syntheticWindowsMaterials(root))
        : syntheticWindowsMaterials(root),
    coordinator: coordinator,
  );
  await materials.probe();
  if (!materials.isAvailable) {
    stdout.writeln('BLOCKED');
    return;
  }
  final accounts = SecureLocalAccountStore(materials);
  try {
    switch (command) {
      case 'retain':
        final state = await accounts.retain(args[2], retainSession: true);
        final key = await accounts.cacheKey(state.account!);
        stdout.writeln(
          jsonEncode({
            'id': state.account!.id,
            'key': base64Encode(key),
            'generation': state.generation,
          }),
        );
      case 'signOut':
        await accounts.signOut();
        stdout.writeln('OK');
      case 'switch':
        await accounts.retain('fixture-other', retainSession: true);
        stdout.writeln('OK');
      case 'disable':
        final snapshot = (await accounts.capture())!;
        await accounts.revokeIfCurrent(snapshot);
        stdout.writeln('OK');
      case 'remove':
        final state = (await accounts.read())!;
        await accounts.removeAccount(state.account!.id);
        stdout.writeln('OK');
      case 'crash':
        final state = (await accounts.read())!;
        await accounts.cacheKey(state.account!);
      case 'probe':
        stdout.writeln('OK');
      default:
        throw ArgumentError('未知合成操作');
    }
  } on SecureMaterialCoordinationException {
    stdout.writeln('BLOCKED');
  }
}
