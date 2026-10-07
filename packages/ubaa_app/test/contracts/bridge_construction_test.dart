import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import '../support/bridge/recording_client.dart'
    show FixtureCharacterizationBridgeClient;

void main() {
  test('后端构造持有同一客户端且不触发原生调用', () {
    final client = FixtureCharacterizationBridgeClient();
    final backend = BridgeBackend(client);
    expect(backend.client, same(client));
    expect(client.calls, isEmpty);
  });
}
