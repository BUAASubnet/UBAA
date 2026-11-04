import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ubaa_app/command.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import '../../../lib/command_main.dart';
import '../../../../../packages/ubaa_platform/test/support/shared_account_worker.dart'
    show syntheticWindowsMaterials;

const _configured = String.fromEnvironment('UBAA_COMMAND_EVIDENCE_DIR');
Directory get _root {
  final configured = _configured.isNotEmpty
      ? _configured
      : Platform.environment['UBAA_COMMAND_EVIDENCE_DIR'] ?? '';
  if (configured.isEmpty || !Directory(configured).isAbsolute)
    throw StateError('必须指定私有合成目录');
  return Directory(configured);
}

Future<CommandMaterials> _materials(String? configured) async {
  final root = _root;
  await root.create(recursive: true);
  final data = await Directory('${root.path}/data').create(recursive: true);
  if (configured != null &&
      Directory(configured).absolute.path != data.absolute.path)
    throw StateError('合成入口只使用指定目录');
  final materials = SecureMaterialStore(
    transport: syntheticWindowsMaterials(root),
    coordinator: MaterialCoordinator(
      directory: Directory('${root.path}/coordination'),
    ),
  );
  await materials.probe();
  if (!materials.isAvailable) throw StateError('合成材料不可用');
  return CommandMaterials(directory: data.path, materials: materials);
}

@pragma('vm:entry-point')
Future<void> commandMain(List<String> arguments) =>
    runEngineCommand(arguments, openMaterials: _materials);

/// GUI 保持真实窗口、Engine 和独立句柄，私有 loopback 端口只用于查询合成状态。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final environment = await _materials(null);
  final accounts = SecureLocalAccountStore(environment.materials);
  var snapshot = await accounts.capture();
  if (snapshot?.state.account == null) {
    await accounts.retain('synthetic-command-user', retainSession: true);
    snapshot = await accounts.capture();
  }
  final account = snapshot!.state.account!;
  final binding = await accounts.bindSnapshot(snapshot);
  final scope = await BridgeSharedAccount.capture(
    directory: binding.directory,
    generation: BigInt.from(binding.generation),
  );
  final agenda = await BridgeAgendaStore.openShared(
    configDir: environment.directory,
    accountId: account.id,
    scope: scope,
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      if (request.uri.path == '/count') {
        final count = await agenda.unsyncedCount();
        request.response.write(
          jsonEncode({
            'count': count,
            'alias': account.id,
            'directory': environment.directory,
          }),
        );
      } else if (request.uri.path == '/revoke') {
        await accounts.signOut();
        request.response.write('ok');
      } else if (request.uri.path == '/close') {
        agenda.dispose();
        request.response.write('closed');
      } else {
        request.response.statusCode = 404;
      }
    } on Object {
      request.response.statusCode = 409;
      request.response.write('stale');
    }
    await request.response.close();
  });
  await File('${_root.path}/gui-ready.json').writeAsString(
    jsonEncode({
      'port': server.port,
      'pid': pid,
      'alias': account.id,
      'directory': environment.directory,
    }),
    flush: true,
  );
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('共享命令合成验收'))),
    ),
  );
}
