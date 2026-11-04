import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/src/controller/features/bhpan/service.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('类型化读取保留范围与文件属性，公开投影不携带业务授权', () async {
    final client = _Client();
    final service = BridgeBackend(client).bhpan;
    final page = await service.read(
      const BhpanRead(BhpanReadView.personalRoot),
    );
    expect(client.query!.view, BridgeBhpanReadView.personalRoot);
    expect(page.range, BhpanListRange.unknown);
    expect(page.items.single.bytes, 12);
    expect(page.items.single.modifiedAt, DateTime.utc(2026, 11, 5));
    final intent = await service.prepare(
      const BhpanMutation(
        BhpanMutationKind.rename,
        target: 'file-handle',
        name: '新名称',
      ),
    );
    expect(client.write!.kind, BridgeBhpanMutationKind.rename);
    expect(client.write!.target, 'file-handle');
    expect(intent.operation, WriteOperation.bhpan);
    expect(intent.intentId, 'bhpan:confirmation');
  });
  test('账号代次变化拒绝迟到列表与后续准备', () async {
    final client = _Client()..gate = Completer<BridgeBhpanPage>();
    var current = true;
    final service = GuardedBhpanService(
      BridgeBackend(client).bhpan,
      () => current,
    );
    final pending = service.read(const BhpanRead(BhpanReadView.personalRoot));
    current = false;
    final expectation = expectLater(
      pending,
      throwsA(
        isA<UiError>().having(
          (e) => e.code,
          '错误码',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    client.gate!.complete(_page);
    await expectation;
    await expectLater(
      service.prepare(
        const BhpanMutation(BhpanMutationKind.recycle, target: 'file-handle'),
      ),
      throwsA(isA<UiError>()),
    );
    expect(client.write, isNull);
  });
  test('网盘写入沿用公共提交与丢弃入口，收据保留分享', () async {
    final client = _Client();
    final backend = BridgeBackend(client);
    final result = await backend.commitWrite('bhpan:confirmation');
    expect(result.operation, WriteOperation.bhpan);
    expect(result.bhpanReceipt!.share!.passwordRequired, isTrue);
    await backend.discardWriteIntent('bhpan:confirmation');
    expect(client.committed, 'confirmation');
    expect(client.discarded, 'confirmation');
  });
}

final _page = BridgeBhpanPage(
  items: [
    BridgeBhpanItem(
      handle: 'file-handle',
      name: '测试文件',
      kind: BridgeBhpanItemKind.file,
      scope: BridgeBhpanScope.personal,
      bytes: BigInt.from(12),
      modifiedAt: 1793836800,
    ),
  ],
  range: BridgeBhpanListRange.unknown,
  route: BridgeConnectionMode.direct,
  fetchedAt: 1793836800,
);

class _Client implements BridgeClient {
  Completer<BridgeBhpanPage>? gate;
  BridgeBhpanQuery? query;
  BridgeBhpanWrite? write;
  String? committed, discarded;
  @override
  int contractVersion() => 47;
  @override
  Future<BridgeBhpanPage> bhpanRead({required BridgeBhpanQuery query}) async {
    this.query = query;
    return gate == null ? _page : gate!.future;
  }

  @override
  Future<BridgeBhpanPrepared> bhpanPrepare({
    required BridgeBhpanWrite request,
  }) async {
    write = request;
    return const BridgeBhpanPrepared(
      handle: 'confirmation',
      description: '重命名测试文件',
      route: BridgeConnectionMode.direct,
    );
  }

  @override
  Future<BridgeBhpanReceipt> bhpanCommit({required String handle}) async {
    committed = handle;
    return const BridgeBhpanReceipt(
      share: BridgeBhpanShare(
        handle: 'share-handle',
        title: '合成分享',
        expiresAt: '1970-01-01T08:00:00+08:00',
        passwordRequired: true,
        limitedTimes: -1,
        permissions: [BridgeBhpanPermission.display],
        canUpdate: true,
      ),
    );
  }

  @override
  Future<void> bhpanDiscard({required String handle}) async {
    discarded = handle;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
