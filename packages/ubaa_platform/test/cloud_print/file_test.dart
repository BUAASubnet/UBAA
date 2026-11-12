import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/src/infrastructure/cloud_print_file.dart';

void main() {
  test('逐份保留原始数据，同名避让，拒绝离开所选目录', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ubaa-cloud-print-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final folder = LocalPrintDownloadFolder(directory);
    final existing = File.fromUri(directory.uri.resolve('scan.pdf'));
    await existing.writeAsBytes([0]);

    expect(
      await folder.save('scan.pdf', Uint8List.fromList([1, 2, 3]), () => true),
      'scan (1).pdf',
    );
    expect(await existing.readAsBytes(), [0]);
    expect(
      await File.fromUri(directory.uri.resolve('scan%20(1).pdf')).readAsBytes(),
      [1, 2, 3],
    );
    expect(
      await folder.save('../notes.pdf', Uint8List.fromList([4]), () => true),
      '_notes.pdf',
    );
    await expectLater(
      folder.save('other.pdf', Uint8List(1), () => false),
      throwsA(isA<UiError>()),
    );
    expect(
      await File.fromUri(directory.uri.resolve('other.pdf')).exists(),
      isFalse,
    );
  });
}
