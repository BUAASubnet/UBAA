import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';

const root = BhpanItem(
  handle: 'root',
  name: '个人文档库',
  kind: BhpanItemKind.folder,
  scope: BhpanScope.personal,
);
const folder = BhpanItem(
  handle: 'folder',
  name: '课程资料',
  kind: BhpanItemKind.folder,
  scope: BhpanScope.personal,
);
const file = BhpanItem(
  handle: 'file',
  name: '报告.txt',
  kind: BhpanItemKind.file,
  scope: BhpanScope.personal,
  bytes: 120,
);
BhpanPage page(List<BhpanItem> items) => BhpanPage(
  items: items,
  range: BhpanListRange.unknown,
  route: ConnectionMode.direct,
  fetchedAt: DateTime.utc(2026, 11, 5),
);

class Files implements BhpanService {
  @override
  Future<BhpanDownloadReceipt> download(
    List<String> handles,
    String name,
    String path,
    bool overwrite,
    BhpanTransferTask transfer,
  ) async => throw UnimplementedError();

  @override
  BhpanTransferTask createTransfer() => Transfer();
  @override
  Future<BhpanDownloadPreparation> downloadPreparation(
    List<String> handles,
    String name,
  ) async => throw UnimplementedError();
  final reads = <BhpanRead>[];
  List<BhpanItem> contents = [folder, file];
  Completer<BhpanPage>? gate;
  @override
  Future<BhpanPage> read(BhpanRead query) async {
    reads.add(query);
    if (gate != null) return gate!.future;
    if (query.view == BhpanReadView.personalRoot) return page([root]);
    if (query.target == 'folder') return page([]);
    return page(contents);
  }

  @override
  Future<BhpanCapabilities> capabilities() async => const BhpanCapabilities(
    directMetadata: BhpanCapability.available,
    webvpn: BhpanCapability.unverified,
    objectTransfer: BhpanCapability.available,
    conditionalReplace: BhpanCapability.unverified,
    limitations: [],
  );
  @override
  Future<void> login() async {}
  @override
  Future<BhpanSize> size(String item) async =>
      const BhpanSize(folders: 1, files: 1, bytes: 120);
  @override
  Future<String> suggestName(String parent, String name) async => '$name (1)';
  @override
  Future<List<BhpanShare>> shares({String? item}) async => [];
  @override
  Future<String> shareLink(String share) async =>
      'https://bhpan.buaa.edu.cn/link/synthetic';
  @override
  Future<WriteIntent> prepare(BhpanMutation request) async =>
      throw UnimplementedError();
}

class Transfer implements BhpanTransferTask {
  bool cancelled = false;
  int reads = 0;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<BhpanTransferProgress> progress() async {
    reads++;
    return BhpanTransferProgress(
      phase: cancelled
          ? BhpanTransferPhase.cancelled
          : BhpanTransferPhase.queued,
      bytes: 0,
      total: 0,
    );
  }
}
