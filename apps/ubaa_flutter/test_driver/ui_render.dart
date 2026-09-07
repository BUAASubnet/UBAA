import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final destination = Platform.environment['UBAA_UI_EVIDENCE_DIR'];
  if (destination == null || !destination.startsWith('/')) {
    throw ArgumentError('UBAA_UI_EVIDENCE_DIR 必须是本次运行的私有绝对路径');
  }
  final directory = Directory(destination);
  if (await directory.exists() && !await directory.list().isEmpty) {
    throw ArgumentError('证据目录必须为空，不能改动已有目录内容或权限');
  }
  await directory.create(recursive: true);
  final permissions = await Process.run('chmod', <String>[
    '700',
    directory.path,
  ]);
  if (permissions.exitCode != 0) throw StateError('无法设置证据目录私有权限');
  final names = <String>{};
  String checkedName(Object? value) {
    if (value is! String || !RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
      throw ArgumentError('截图名称不符合 ASCII 安全格式');
    }
    return value;
  }

  await runZoned(
    () => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        checkedName(name);
        final file = File('${directory.path}/$name.png');
        if (await file.exists()) throw StateError('拒绝覆盖已有截图：$name');
        if (bytes.length < 8 ||
            bytes[0] != 137 ||
            bytes[1] != 80 ||
            bytes[2] != 78 ||
            bytes[3] != 71) {
          throw StateError('原生截图不是 PNG：$name');
        }
        await file.writeAsBytes(bytes, flush: true);
        names.add(name);
        return true;
      },
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        final records = data?['uiEvidence'] as List? ?? <Object?>[];
        for (final raw in records) {
          final record = Map<String, Object?>.from(raw as Map);
          final name = checkedName(record['name']);
          record['pngSaved'] = names.contains(name);
          await File('${directory.path}/$name.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert(record),
            flush: true,
          );
        }
        // 禁止使用 SDK 默认 writeResponseData，否则会写入完整截图字节数组。
        await File('${directory.path}/manifest.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'savedScreenshots': names.toList(),
            'metadataCount': records.length,
            'evidence': 'native-ios-synthetic-ui',
            'acceptance': 'requires-test-result-and-visual-review',
          }),
          flush: true,
        );
      },
    ),
    // SDK 某些分支打印完整 response，其中含图像字节；这里只输出固定摘要。
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(
          zone,
          line.startsWith('result ') || line.contains('"bytes"')
              ? '原生截图响应已交给证据保存器，省略图像字节。'
              : line,
        );
      },
    ),
  );
}
