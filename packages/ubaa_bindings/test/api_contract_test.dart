import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

void main() {
  test('生成 API 暴露固定初始化与 hello 入口', () {
    expect(RustLib.init, isA<Function>());
    expect(bridgeHello, isA<Function>());
  });
}
