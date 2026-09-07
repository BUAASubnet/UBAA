import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ui_render.dart' as render;

/// 保留原Flutter截图driver，仅增加合成测试的整机键盘截图握手。
Future<void> main() async {
  final runId = Platform.environment['UBAA_KEYBOARD_RUN_ID'];
  final device = Platform.environment['UBAA_UI_SIMULATOR_ID'];
  final directory = Platform.environment['UBAA_UI_EVIDENCE_DIR'];
  if (runId == null ||
      runId.isEmpty ||
      device == null ||
      !RegExp(r'^[A-Fa-f0-9-]{36}$').hasMatch(device) ||
      directory == null ||
      !directory.startsWith('/')) {
    throw ArgumentError('缺少本轮runId、模拟器ID或私有证据绝对目录');
  }
  unawaited(
    _captureDevices(runId, device, directory).catchError((Object _) {
      stderr.writeln('整机键盘截图握手失败，拒绝标记通过。');
      exit(1);
    }),
  );
  await render.main();
}

Future<void> _captureDevices(
  String runId,
  String device,
  String directory,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  final saved = <String>{};
  try {
    while (true) {
      Map<String, dynamic>? status;
      try {
        final request = await client.getUrl(
          Uri.http('127.0.0.1:48764', '/status', {'runId': runId}),
        );
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw StateError('本轮握手拒绝');
        }
        status =
            jsonDecode(await utf8.decoder.bind(response).join())
                as Map<String, dynamic>;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      if (status['runId'] != runId) throw StateError('运行标识不一致');
      final scene = status['scene'];
      if (status['phase'] == 'capture' &&
          scene is String &&
          !saved.contains(scene)) {
        if (!RegExp(r'^(dark|light)-library-keyboard$').hasMatch(scene)) {
          throw StateError('未知键盘截图场景');
        }
        final file = File('$directory/$scene-device.png');
        if (await file.exists()) throw StateError('拒绝覆盖整机截图');
        final result = await Process.run('xcrun', [
          'simctl',
          'io',
          device,
          'screenshot',
          '--type=png',
          file.path,
        ]);
        if (result.exitCode != 0) throw StateError('原生整机截图失败');
        final handle = await file.open();
        final header = await handle.read(24);
        await handle.close();
        if (header.length != 24 ||
            header[0] != 137 ||
            header[1] != 80 ||
            header[2] != 78 ||
            header[3] != 71) {
          throw StateError('整机截图不是PNG');
        }
        final bytes = ByteData.sublistView(Uint8List.fromList(header));
        await File('$directory/$scene-device.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'runId': runId,
            'scene': scene,
            'screenshot': '$scene-device.png',
            'screenshotSource': 'simctl-native-device-including-system-ui',
            'deviceId': device,
            'physicalWidth': bytes.getUint32(16),
            'physicalHeight': bytes.getUint32(20),
            'dateUtc': DateTime.now().toUtc().toIso8601String(),
            'backend': 'synthetic-inspection',
          }),
          flush: true,
        );
        saved.add(scene);
        final ack = await client.postUrl(
          Uri.http('127.0.0.1:48764', '/ack', {'runId': runId, 'scene': scene}),
        );
        final response = await ack.close();
        final record =
            jsonDecode(await utf8.decoder.bind(response).join()) as Map;
        if (response.statusCode != HttpStatus.ok ||
            record['runId'] != runId ||
            record['phase'] != 'accepted') {
          throw StateError('截图确认失败');
        }
        stdout.writeln('已保存本轮整机键盘截图：$scene');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  } finally {
    client.close(force: true);
  }
}
