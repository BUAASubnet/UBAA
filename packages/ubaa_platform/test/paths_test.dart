import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('目录未初始化不能猜测 HOME', () {
    final directory = PrivateConfigDirectory(
      environment: {'HOME': '/synthetic/home'},
    );
    expect(directory.resolve, throwsA(isA<Exception>()));
  });
}
