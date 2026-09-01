import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

void main() {
  test('生成 API 暴露固定初始化与 hello 入口', () {
    expect(RustLib.init, isA<Function>());
    expect(bridgeHello, isA<Function>());
  });

  test('生成 API 暴露 opaque client、路线设置和安全资料白名单', () {
    expect(BridgeClient.open, isA<Function>());
    expect(BridgeRoutePolicy.values, hasLength(3));
    expect(BridgeErrorCode.values, contains(BridgeErrorCode.clientDisposed));

    const profile = BridgeUserProfile(
      username: 'student',
      name: '同学',
      schoolId: 'S1',
      email: null,
      phone: null,
      idCardTypeName: null,
    );
    expect(profile.username, 'student');
    // 证件号字段不在生成类型中，防止把高敏感资料带入 Dart API。
    expect(profile.idCardTypeName, isNull);
  });
}
