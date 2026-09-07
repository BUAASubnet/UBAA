import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

void main() {
  test('同次资料读取保留四个不同白名单值且不增加请求', () async {
    final client = _ProfileClient(
      const BridgeUserProfile(
        username: ' fixture-account ',
        name: ' 合成姓名 ',
        schoolId: ' SCHOOL-SYNTHETIC ',
        email: ' fixture@example.invalid ',
        phone: ' 000-synthetic-phone ',
        idCardTypeName: ' 合成证件类型 ',
      ),
    );
    final user = (await BridgeBackend(client).userInfo())!;
    expect(user.schoolId, 'SCHOOL-SYNTHETIC');
    expect(user.email, 'fixture@example.invalid');
    expect(user.phone, '000-synthetic-phone');
    expect(user.idCardTypeName, '合成证件类型');
    expect(user.username, 'fixture-account');
    expect(user.preferredName, '合成姓名');
    expect(user.department, isNull);
    expect(client.calls, 1);
  });
  test('可选资料缺失或空白保持null且姓名回退账号', () async {
    for (final value in <String?>[null, '', '   ']) {
      final client = _ProfileClient(
        BridgeUserProfile(
          username: 'fixture',
          name: value,
          schoolId: value,
          email: value,
          phone: value,
          idCardTypeName: value,
        ),
      );
      final user = (await BridgeBackend(client).userInfo())!;
      expect(user.schoolId, isNull);
      expect(user.email, isNull);
      expect(user.phone, isNull);
      expect(user.idCardTypeName, isNull);
      expect(user.preferredName, 'fixture');
      expect(client.calls, 1);
    }
  });
  test('用户名缺失时学校标识不能替代原认证身份', () async {
    for (final username in <String?>[null, '', '   ']) {
      final client = _ProfileClient(
        BridgeUserProfile(username: username, schoolId: 'SCHOOL-SYNTHETIC'),
      );
      expect(await BridgeBackend(client).userInfo(), isNull);
      expect(client.calls, 1);
    }
  });
}

class _ProfileClient implements BridgeClient {
  _ProfileClient(this.profile);
  final BridgeUserProfile profile;
  int calls = 0;
  @override
  int contractVersion() => 9;
  @override
  Future<BridgeRoutedUserProfile> userInfo() async {
    calls++;
    return BridgeRoutedUserProfile(
      data: profile,
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('资料投影不应调用其他接口');
}
