import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import '../context.dart';
import '../../controller/error_mapper.dart' show UbaaErrorMapper;
import '../support/mapping.dart' show bridgeMapError, bridgeToConnectionMode;
import 'projection.dart';

/// typed 模型适配，协议字段、文件身份与授权留在 Core。
final class BridgeBhpanService implements BhpanService {
  BridgeBhpanService(this.context);
  final BridgeContext context;
  @override
  Future<BhpanDownloadReceipt> download(
    List<String> handles,
    String name,
    String path,
    bool overwrite,
    BhpanTransferTask transfer,
  ) => _run(() async {
    if (transfer is! BridgeBhpanTransferTask ||
        !identical(transfer.client, context.client))
      throw const BackendException(UbaaErrorCode.invalidInput);
    final receipt = await context.client.bhpanDownload(
      handles: handles,
      name: name,
      path: path,
      overwrite: overwrite,
      transfer: transfer.control,
    );
    return BhpanDownloadReceipt(
      bytes: receipt.bytes.toInt(),
      batch: receipt.batch,
    );
  });
  @override
  Future<BhpanDownloadPreparation> downloadPreparation(
    List<String> handles,
    String name,
  ) => _run(() async {
    final p = await context.client.bhpanDownloadPreparation(
      handles: handles,
      name: name,
    );
    return BhpanDownloadPreparation(
      host: p.host,
      port: p.port,
      method: p.method,
      headerNames: List.unmodifiable(p.headerNames),
      batch: p.batch,
      destinationVerified: p.destinationVerified,
    );
  });
  @override
  BhpanTransferTask createTransfer() =>
      BridgeBhpanTransferTask(context.client, BridgeBhpanTransfer());
  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on BridgeError catch (e) {
      final mapped = UbaaErrorMapper.fromException(bridgeMapError(e));
      // 透传错误类别，界面据此区分「会话过期」与真正的权限不足。
      throw UiError(
        code: mapped.code,
        title: mapped.title,
        message: e.message,
        kind: mapped.kind,
        resolvedRoute: mapped.resolvedRoute,
        retryable: mapped.retryable,
      );
    }
  }

  @override
  Future<BhpanCapabilities> capabilities() => _run(() async {
    final c = await context.client.bhpanCapabilities();
    return BhpanCapabilities(
      directMetadata: BhpanCapability.values[c.directMetadata.index],
      fastUpload: BhpanCapability.values[c.fastUpload.index],
      webvpn: BhpanCapability.values[c.webvpn.index],
      objectTransfer: BhpanCapability.values[c.objectTransfer.index],
      conditionalReplace: BhpanCapability.values[c.conditionalReplace.index],
      limitations: List.unmodifiable(c.limitations),
    );
  });
  @override
  Future<void> login() => _run(context.client.bhpanLogin);
  @override
  Future<BhpanPage> read(BhpanRead q) => _run(() async {
    final query = BridgeBhpanQuery(
      view: BridgeBhpanReadView.values[q.view.index],
      root: BridgeBhpanRootKind.values[q.root.index],
      target: q.target,
      link: q.link,
      password: q.password,
    );
    return bhpanPage(await context.client.bhpanRead(query: query));
  });
  @override
  Future<BhpanSize> size(String item) => _run(() async {
    final s = await context.client.bhpanSize(item: item);
    return BhpanSize(
      folders: s.folders.toInt(),
      files: s.files.toInt(),
      bytes: s.bytes.toInt(),
    );
  });
  @override
  Future<String> suggestName(String parent, String name) =>
      _run(() => context.client.bhpanSuggestName(parent: parent, name: name));
  @override
  Future<List<BhpanShare>> shares({String? item}) => _run(
    () async => List.unmodifiable(
      (await context.client.bhpanShares(item: item)).map(bhpanShare),
    ),
  );
  @override
  Future<String> shareLink(String share) =>
      _run(() => context.client.bhpanShareLink(share: share));
  @override
  Future<WriteIntent> prepare(BhpanMutation r) => _run(() async {
    if (r.kind == BhpanMutationKind.uploadFast ||
        r.kind == BhpanMutationKind.upload) {
      final source = r.source, transfer = r.transfer;
      if (source == null ||
          transfer is! BridgeBhpanTransferTask ||
          !identical(transfer.client, context.client))
        throw const BackendException(UbaaErrorCode.invalidInput);
      final p = r.kind == BhpanMutationKind.uploadFast
          ? await context.client.bhpanPrepareFastUpload(
              parent: r.target,
              path: source.path,
              name: source.name,
              transfer: transfer.control,
            )
          : await context.client.bhpanPrepareUpload(
              parent: r.target,
              path: source.path,
              name: source.name,
              transfer: transfer.control,
            );
      return _intent(p);
    }
    final input = BridgeBhpanWrite(
      kind: BridgeBhpanMutationKind.values[r.kind.index],
      target: r.target,
      name: r.name,
      destination: r.destination,
      settings: r.settings == null ? null : _settings(r.settings),
    );
    final p = await context.client.bhpanPrepare(request: input);
    return _intent(p);
  });
}

WriteIntent _intent(BridgeBhpanPrepared p) => WriteIntent(
  intentId: 'bhpan:${p.handle}',
  operation: WriteOperation.bhpan,
  targetSummary: p.description,
  resolvedRoute: bridgeToConnectionMode(p.route),
  warnings: const [],
  expiresAt: DateTime.now().add(const Duration(minutes: 4)),
  requestDigest: '',
);

final class BridgeBhpanTransferTask implements BhpanTransferTask {
  BridgeBhpanTransferTask(this.client, this.control);
  final BridgeClient client;
  final BridgeBhpanTransfer control;
  @override
  void cancel() => control.cancel();
  @override
  Future<BhpanTransferProgress> progress() async {
    final p = control.progress();
    return BhpanTransferProgress(
      phase: BhpanTransferPhase.values[p.phase.index],
      bytes: p.bytes.toInt(),
      total: p.total.toInt(),
    );
  }
}

BridgeBhpanShareSettings _settings(BhpanShareSettings? s) {
  if (s == null) throw const BackendException(UbaaErrorCode.invalidInput);
  return BridgeBhpanShareSettings(
    title: s.title,
    expiresAt: s.expiresAt,
    password: s.password,
    keepPassword: s.keepPassword,
    limitedTimes: s.limitedTimes,
    permissions: s.permissions
        .map((p) => BridgeBhpanPermission.values[p.index])
        .toList(),
  );
}

Future<WriteCommitResult> bridgeBhpanCommit(
  BridgeContext context,
  String id,
) async {
  try {
    final receipt = await context.client.bhpanCommit(handle: id.substring(6));
    return WriteCommitResult(
      operation: WriteOperation.bhpan,
      success: true,
      message: '操作成功',
      outcomeUnknown: false,
      resolvedRoute: ConnectionMode.direct,
      bhpanReceipt: BhpanReceipt(
        item: receipt.item == null ? null : bhpanItem(receipt.item!),
        share: receipt.share == null ? null : bhpanShare(receipt.share!),
      ),
    );
  } on BridgeError catch (e) {
    throw bridgeMapError(e);
  } on Object {
    throw const BackendException(UbaaErrorCode.outcomeUnknown);
  }
}
