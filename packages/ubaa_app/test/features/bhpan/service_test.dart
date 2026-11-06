import 'dart:async';
import 'package:ubaa_app/src/bridge/bhpan/service.dart';
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
  test('普通上传和下载复用同一个客户端传输控制并保留文件交付参数', () async {
    final client = _Client();
    final service = BridgeBackend(client).bhpan;
    final control = _Transfer();
    final task = BridgeBhpanTransferTask(client, control);
    await service.prepare(
      BhpanMutation(
        BhpanMutationKind.upload,
        target: 'parent',
        source: const BhpanLocalFile(
          path: '/selected/source',
          name: 'notes.txt',
        ),
        transfer: task,
      ),
    );
    expect(client.uploadPath, '/selected/source');
    expect(identical(client.transfer, control), true);
    final result = await service.download(
      ['file'],
      'notes',
      '/selected/output',
      true,
      task,
    );
    expect(result.bytes, 12);
    expect(client.destination, '/selected/output');
    expect(client.overwrite, true);
    expect(identical(client.transfer, control), true);
    await expectLater(
      service.download(
        ['file'],
        'notes',
        'unused',
        false,
        BridgeBhpanTransferTask(_Client(), control),
      ),
      throwsA(isA<BackendException>()),
    );
  });
  test('下载等待期间换号拒绝迟到文件收据', () async {
    final client = _Client()
      ..downloadGate = Completer<BridgeBhpanDownloadReceipt>();
    var current = true;
    final service = GuardedBhpanService(
      BridgeBackend(client).bhpan,
      () => current,
    );
    final pending = service.download(
      ['file'],
      'notes',
      '/selected/output',
      false,
      BridgeBhpanTransferTask(client, _Transfer()),
    );
    current = false;
    final expectation = expectLater(pending, throwsA(isA<UiError>()));
    client.downloadGate!.complete(
      BridgeBhpanDownloadReceipt(bytes: BigInt.from(12), batch: false),
    );
    await expectation;
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

class _Transfer implements BridgeBhpanTransfer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  String? uploadPath, destination;
  bool? overwrite;
  BridgeBhpanTransfer? transfer;
  Completer<BridgeBhpanDownloadReceipt>? downloadGate;
  @override
  Future<BridgeBhpanPrepared> bhpanPrepareUpload({
    required String parent,
    required String path,
    required String name,
    required BridgeBhpanTransfer transfer,
  }) async {
    uploadPath = path;
    this.transfer = transfer;
    return const BridgeBhpanPrepared(
      handle: 'upload-confirmation',
      description: '上传文件',
      route: BridgeConnectionMode.direct,
    );
  }

  @override
  Future<BridgeBhpanDownloadReceipt> bhpanDownload({
    required List<String> handles,
    required String name,
    required String path,
    required bool overwrite,
    required BridgeBhpanTransfer transfer,
  }) async {
    destination = path;
    this.overwrite = overwrite;
    this.transfer = transfer;
    return downloadGate == null
        ? BridgeBhpanDownloadReceipt(bytes: BigInt.from(12), batch: false)
        : downloadGate!.future;
  }

  Completer<BridgeBhpanPage>? gate;
  BridgeBhpanQuery? query;
  BridgeBhpanWrite? write;
  String? committed, discarded;
  @override
  int contractVersion() => 53;
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
