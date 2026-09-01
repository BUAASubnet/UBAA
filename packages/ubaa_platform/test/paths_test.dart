import 'dart:io';

import 'package:test/test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('默认配置目录是绝对的应用私有目录', () {
    final path = defaultConfigDirectory();
    expect(Directory(path).isAbsolute, isTrue);
    expect(path.split(Platform.pathSeparator).last, 'UBAA');
  });
}
