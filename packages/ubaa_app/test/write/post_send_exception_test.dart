import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/write/fixtures.dart';

void main() {
  test('上游生效后未分类异常提示先核对并回读且不重复发送', () async {
    var upstreamWrites = 0;
    var reads = 0;
    ConnectionMode? readRoute;
    final coordinator = WriteCoordinator(
      now: () => fixtureNow,
      commit: (_) async {
        upstreamWrites++;
        throw StateError('/private/token=synthetic');
      },
      receiptVerifier: WriteReceiptVerifier(
        refreshPinnedAfterWrite: (_, _, route) async {
          expect(upstreamWrites, 1);
          readRoute = route;
          reads++;
        },
      ),
    );
    coordinator.setIntent(fixtureIntent());
    final outcome = await coordinator.confirmForUi();
    expect(outcome?.error?.code, UbaaErrorCode.outcomeUnknown);
    expect(outcome?.message, contains('不要重复提交'));
    expect(reads, 1);
    expect(readRoute, ConnectionMode.webvpn);
    expect(await coordinator.confirmForUi(), isNull);
    expect(upstreamWrites, 1);
    coordinator.dispose();
  });
}
