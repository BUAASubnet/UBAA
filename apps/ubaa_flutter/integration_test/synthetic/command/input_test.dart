import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/command.dart';
import '../../support/rust_library.dart';

final class _Input implements CommandIO {
  final output = <int>[];
  @override
  Future<void> configure({required bool local}) async {}
  @override
  Future<List<int>?> readLine({required bool secret}) async => [10];
  @override
  Future<List<int>> readBody() => throw StateError('此输入不能读取请求正文');
  @override
  Future<void> writeStdout(List<int> bytes) async => output.addAll(bytes);
  @override
  Future<void> writeStderr(List<int> bytes) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实命令准备在访问材料和账号前拒绝密码与阳光输入', (tester) async {
    await tester.runAsync(() async {
      await initializeRustLibrary();
      for (final arguments in [
        [
          'ubaa',
          '--json',
          'auth',
          'login',
          '--username',
          'synthetic',
          '--password-stdin',
        ],
        [
          'ubaa',
          '--json',
          'ygdk',
          'submit',
          '--classify-id',
          '1',
          '--item-id',
          '1',
          '--start-time',
          'bad-time',
          '--end-time',
          'bad-time',
          '--photo',
          '.ubaa_local/command_delivery/missing_photo.jpg',
          '--confirm-write',
        ],
        [
          'ubaa',
          '--json',
          'ygdk',
          'submit',
          '--classify-id',
          '1',
          '--item-id',
          '1',
          '--start-time',
          '2026-11-05 08:00',
          '--end-time',
          '2026-11-05 09:00',
          '--photo',
          '.ubaa_local/command_delivery/missing_photo.jpg',
          '--confirm-write',
        ],
      ]) {
        final input = _Input();
        var materialCalls = 0;
        var clientCalls = 0;
        final runtime = CommandRuntime(
          io: input,
          openMaterials: (_) async {
            materialCalls++;
            throw StateError('此入口禁止访问材料或修改账号代次');
          },
          openClient: ({required configDir}) async {
            clientCalls++;
            throw StateError('此入口禁止创建学校客户端');
          },
        );
        expect(
          await runtime.run(arguments, budget: const Duration(seconds: 10)),
          2,
        );
        expect(materialCalls, 0);
        expect(clientCalls, 0);
        final envelope =
            jsonDecode(utf8.decode(input.output)) as Map<String, dynamic>;
        expect(envelope['schemaVersion'], 14);
        expect(envelope['ok'], false);
        expect(
          (envelope['error'] as Map<String, dynamic>)['code'],
          'invalid_input',
        );
      }
    });
  });
}
