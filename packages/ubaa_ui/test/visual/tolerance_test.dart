import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/visual/tolerant_comparator.dart';

/// 100×100 白底图，前 [changed] 个像素改为黑色；每个像素占 0.01%。
Future<Uint8List> _image(int changed) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..color = Colors.white,
    );
  for (var index = 0; index < changed; index++) {
    canvas.drawRect(
      Rect.fromLTWH((index % 100).toDouble(), (index ~/ 100).toDouble(), 1, 1),
      Paint()..color = Colors.black,
    );
  }
  final image = await recorder.endRecording().toImage(100, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  testWidgets('golden 容差只放过渲染级差异，可见变化仍失败', (tester) async {
    expect(
      goldenFileComparator,
      isA<TolerantGoldenComparator>(),
      reason: '包级 flutter_test_config 必须替换默认比较器',
    );
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('ubaa-golden-');
      try {
        final testFile = Uri.file('${directory.path}/sample_test.dart');
        final golden = Uri.parse('sample.png');
        await File(
          '${directory.path}/sample.png',
        ).writeAsBytes(await _image(0));
        final rendering = await _image(10); // 0.1%，与 CI 抗锯齿差异同量级
        final visible = await _image(50); // 0.5%

        await expectLater(
          LocalFileComparator(testFile).compare(rendering, golden),
          throwsA(isA<FlutterError>()),
          reason: '默认比较器连渲染级差异也拒绝',
        );
        expect(
          await TolerantGoldenComparator(testFile).compare(rendering, golden),
          isTrue,
        );
        await expectLater(
          TolerantGoldenComparator(testFile).compare(visible, golden),
          throwsA(isA<FlutterError>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
