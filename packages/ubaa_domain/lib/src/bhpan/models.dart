import '../common/route.dart';

enum BhpanRootKind { all, personal, shared, department, group }

enum BhpanItemKind { file, folder }

enum BhpanScope { personal, receivedShare, recycle }

enum BhpanListRange { unknown, firstHundred }

enum BhpanPermission { create, modify, download, preview, display }

enum BhpanReadView { personalRoot, roots, directory, recycle, receivedShare }

enum BhpanMutationKind {
  createFolder,
  rename,
  move,
  copy,
  recycle,
  restore,
  deleteForever,
  createShare,
  updateShare,
  cancelShare,
  uploadFast,
  upload,
}

final class BhpanItem {
  const BhpanItem({
    required this.handle,
    required this.name,
    required this.kind,
    required this.scope,
    this.bytes,
    this.createdAt,
    this.modifiedAt,
  });
  final String handle, name;
  final BhpanItemKind kind;
  final BhpanScope scope;
  final int? bytes;
  final DateTime? createdAt, modifiedAt;
  bool get isFolder => kind == BhpanItemKind.folder;
}

final class BhpanPage {
  const BhpanPage({
    required this.items,
    required this.range,
    required this.route,
    required this.fetchedAt,
  });
  final List<BhpanItem> items;
  final BhpanListRange range;
  final ConnectionMode route;
  final DateTime fetchedAt;
}

final class BhpanSize {
  const BhpanSize({
    required this.folders,
    required this.files,
    required this.bytes,
  });
  final int folders, files, bytes;
}

final class BhpanShare {
  const BhpanShare({
    required this.handle,
    required this.title,
    required this.expiresAt,
    required this.passwordRequired,
    required this.limitedTimes,
    required this.permissions,
    required this.canUpdate,
  });
  final String handle, title, expiresAt;
  final bool passwordRequired, canUpdate;
  final int limitedTimes;
  final List<BhpanPermission> permissions;
}

final class BhpanShareSettings {
  const BhpanShareSettings({
    required this.title,
    this.expiresAt = '1970-01-01T08:00:00+08:00',
    this.password = '',
    this.limitedTimes = -1,
    this.permissions = const [
      BhpanPermission.display,
      BhpanPermission.download,
    ],
  });
  final String title, expiresAt, password;
  final int limitedTimes;
  final List<BhpanPermission> permissions;
}

final class BhpanRead {
  const BhpanRead(
    this.view, {
    this.root = BhpanRootKind.all,
    this.target,
    this.link,
    this.password,
  });
  final BhpanReadView view;
  final BhpanRootKind root;
  final String? target, link, password;
}

final class BhpanMutation {
  const BhpanMutation(
    this.kind, {
    required this.target,
    this.name,
    this.destination,
    this.settings,
    this.source,
    this.transfer,
  });
  final BhpanMutationKind kind;
  final String target;
  final String? name, destination;
  final BhpanShareSettings? settings;
  final BhpanLocalFile? source;
  final BhpanTransferTask? transfer;
}

final class BhpanLocalFile {
  const BhpanLocalFile({
    required this.path,
    required this.name,
    Future<void> Function()? release,
  }) : _release = release;
  final String path, name;
  final Future<void> Function()? _release;
  Future<void> release() async {
    await _release?.call();
  }
}

enum BhpanTransferPhase {
  queued,
  hashingMini,
  hashingFull,
  checking,
  awaitingConfirmation,
  submitting,
  completed,
  cancelled,
  failed,
  outcomeUnknown,
  blocked,
  uploading,
  downloading,
  finalizing,
}

final class BhpanTransferProgress {
  const BhpanTransferProgress({
    required this.phase,
    required this.bytes,
    required this.total,
  });
  final BhpanTransferPhase phase;
  final int bytes, total;
}

abstract interface class BhpanTransferTask {
  Future<BhpanTransferProgress> progress();
  void cancel();
}

final class BhpanReceipt {
  const BhpanReceipt({this.item, this.share});
  final BhpanItem? item;
  final BhpanShare? share;
}

final class BhpanCapabilities {
  const BhpanCapabilities({
    required this.directMetadata,
    this.fastUpload = BhpanCapability.unavailable,
    required this.webvpn,
    required this.objectTransfer,
    required this.conditionalReplace,
    required this.limitations,
  });
  final BhpanCapability directMetadata,
      webvpn,
      objectTransfer,
      conditionalReplace;
  final BhpanCapability fastUpload;
  final List<String> limitations;
}

final class BhpanDownloadPreparation {
  const BhpanDownloadPreparation({
    required this.host,
    required this.port,
    required this.method,
    required this.headerNames,
    required this.batch,
    required this.destinationVerified,
  });
  final String host, method;
  final int port;
  final List<String> headerNames;
  final bool batch, destinationVerified;
}

enum BhpanCapability { available, unverified, unavailable }

final class BhpanDownloadReceipt {
  const BhpanDownloadReceipt({required this.bytes, required this.batch});
  final int bytes;
  final bool batch;
}

/// 系统面板选定的位置或本机暂存文件，正文由 Core 和原生文件通道流式交付。
abstract interface class BhpanDownloadDestination {
  String get path;
  bool get overwrite;
  Future<void> deliver(bool Function() isCurrent);
  Future<void> discard();
}
