import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/ihome/service.dart';
import 'package:ubaa_app/src/controller/features/ihome/service.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class Client implements BridgeClient {
  int calls = 0;
  BridgeIhomeQuery? query;
  Completer<BridgeIhomePageResult>? pending;
  BridgeError? error;
  @override
  Future<BridgeIhomePageResult> ihomePage({
    required BridgeIhomeQuery query,
  }) async {
    this.query = query;
    calls++;
    if (error != null) throw error!;
    return pending?.future ??
        Future.value(
          const BridgeIhomePageResult(
            data: BridgeIhomePage(entries: [], page: 2, lastPage: 3, total: 20),
            route: BridgeRouteDecision(
              policy: BridgeRoutePolicy.webVpn,
              resolvedRoute: BridgeConnectionMode.webVpn,
              network: BridgeNetworkState.offCampus,
              initialRoute: BridgeConnectionMode.webVpn,
              usedFallback: false,
            ),
          ),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const query = IhomeQuery(
  scope: IhomeScope.mine,
  page: 2,
  limit: 15,
  keyword: '',
  filter: IhomeFilter.replyTime,
  categoryId: null,
);
void main() {
  test('查询参数和路线经过类型化投影', () async {
    final client = Client();
    final result = await BridgeIhomeService(client).page(query);
    expect(client.query!.scope, BridgeIhomeScope.mine);
    expect(client.query!.filter, BridgeIhomeFilter.replyTime);
    expect(client.query!.page, 2);
    expect(result.data.total, 20);
    expect(result.route, ConnectionMode.webvpn);
  });
  test('业务错误保留未知结果分类且不携带上游正文', () async {
    final client = Client()
      ..error = const BridgeError(
        code: BridgeErrorCode.outcomeUnknown,
        kind: BridgeErrorKind.upstream,
        retryable: false,
        message: '敏感上游正文',
      );
    await expectLater(
      BridgeIhomeService(client).page(query),
      throwsA(
        isA<UiError>()
            .having((v) => v.code, '错误', UbaaErrorCode.outcomeUnknown)
            .having((v) => v.message.contains('敏感'), '不泄露', false),
      ),
    );
    expect(client.calls, 1);
  });
  test('旧账号页面拒绝请求并丢弃迟到结果', () async {
    final client = Client();
    var current = true;
    final service = GuardedIhomeService(
      BridgeIhomeService(client),
      () => current,
    );
    client.pending = Completer<BridgeIhomePageResult>();
    final read = service.page(query);
    await Future<void>.delayed(Duration.zero);
    current = false;
    final check = expectLater(read, throwsA(isA<UiError>()));
    client.pending!.complete(
      const BridgeIhomePageResult(
        data: BridgeIhomePage(entries: [], page: 1, lastPage: 1, total: 0),
        route: BridgeRouteDecision(
          policy: BridgeRoutePolicy.direct,
          resolvedRoute: BridgeConnectionMode.direct,
          network: BridgeNetworkState.campus,
          initialRoute: BridgeConnectionMode.direct,
          usedFallback: false,
        ),
      ),
    );
    await check;
    await expectLater(service.page(query), throwsA(isA<UiError>()));
    expect(client.calls, 1);
  });
}
