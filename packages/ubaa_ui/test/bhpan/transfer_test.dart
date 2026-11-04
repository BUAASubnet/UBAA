import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support.dart';

class Destination implements BhpanDownloadDestination {
  int deliveries = 0, discards = 0;
  @override
  String get path => '/synthetic/download.txt';
  @override
  bool get overwrite => false;
  @override
  Future<void> deliver(bool Function() current) async {
    expect(current(), true);
    deliveries++;
  }

  @override
  Future<void> discard() async {
    discards++;
  }
}

class DownloadFiles extends Files {
  final downloads = <List<String>>[];
  final transfer = Transfer();
  @override
  BhpanTransferTask createTransfer() => transfer;
  Completer<BhpanDownloadReceipt>? completion;
  @override
  Future<BhpanDownloadReceipt> download(
    List<String> handles,
    String name,
    String path,
    bool overwrite,
    BhpanTransferTask transfer,
  ) async {
    downloads.add(handles);
    return completion == null
        ? const BhpanDownloadReceipt(bytes: 120, batch: false)
        : completion!.future;
  }
}

Future<void> show(WidgetTester tester, BhpanAccess access) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: Scaffold(body: BhpanView(access: access)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> clickDownload(WidgetTester tester, {bool settle = true}) async {
  final row = find.ancestor(
    of: find.text('报告.txt'),
    matching: find.byType(ListTile),
  );
  await tester.tap(
    find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('下载'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('保存面板取消后不下载，确认位置后完整交付一次文件', (tester) async {
    final files = DownloadFiles();
    final destination = Destination();
    var selections = 0;
    await show(
      tester,
      BhpanAccess(
        service: files,
        pickDownload: (name, current) async {
          selections++;
          return selections == 1 ? null : destination;
        },
      ),
    );
    await clickDownload(tester);
    expect(selections, 1);
    expect(files.downloads, isEmpty);
    await clickDownload(tester);
    expect(files.downloads.single, ['file']);
    expect(destination.deliveries, 1);
    expect(destination.discards, 1);
    expect(find.textContaining('已保存'), findsOneWidget);
  });
  testWidgets('普通上传将文件和同一个传输控制交给公共写协调', (tester) async {
    final files = Files();
    BhpanMutation? request;
    await show(
      tester,
      BhpanAccess(
        service: files,
        pickFile: () async =>
            const BhpanLocalFile(path: '/synthetic/input', name: 'notes.txt'),
        runWrite: (value) async {
          request = value;
          return null;
        },
      ),
    );
    await tester.tap(find.text('上传'));
    await tester.pumpAndSettle();
    expect(request!.kind, BhpanMutationKind.upload);
    expect(request!.source!.name, 'notes.txt');
    expect(request!.transfer, isNotNull);
  });
  testWidgets('下载途中取消后不交付文件且清理选定目标', (tester) async {
    final files = DownloadFiles()
      ..completion = Completer<BhpanDownloadReceipt>();
    final destination = Destination();
    await show(
      tester,
      BhpanAccess(service: files, pickDownload: (_, __) async => destination),
    );
    await clickDownload(tester, settle: false);
    await tester.tap(find.text('取消任务'));
    expect(files.transfer.cancelled, true);
    files.completion!.completeError(
      const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '任务已取消',
        message: '文件任务已停止',
      ),
    );
    await tester.pumpAndSettle();
    expect(destination.deliveries, 0);
    expect(destination.discards, 1);
  });
  testWidgets('多选目录和文件使用一次打包下载并交付压缩包', (tester) async {
    final files = DownloadFiles();
    final destination = Destination();
    String? suggested;
    await show(
      tester,
      BhpanAccess(
        service: files,
        pickDownload: (name, _) async {
          suggested = name;
          return destination;
        },
      ),
    );
    for (final name in ['课程资料', '报告.txt']) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await tester.pump();
    }
    await tester.tap(find.text('打包下载'));
    await tester.pumpAndSettle();
    expect(files.downloads.single, ['folder', 'file']);
    expect(suggested, endsWith('.zip'));
    expect(destination.deliveries, 1);
  });
  testWidgets('旧账号迟到下载不交付且不停止新账号的传输进度', (tester) async {
    final old = DownloadFiles()..completion = Completer<BhpanDownloadReceipt>();
    final first = Destination();
    await show(
      tester,
      BhpanAccess(service: old, pickDownload: (_, __) async => first),
    );
    await clickDownload(tester, settle: false);
    final next = DownloadFiles()
      ..completion = Completer<BhpanDownloadReceipt>();
    final second = Destination();
    await show(
      tester,
      BhpanAccess(service: next, pickDownload: (_, __) async => second),
    );
    await clickDownload(tester, settle: false);
    old.completion!.complete(
      const BhpanDownloadReceipt(bytes: 120, batch: false),
    );
    await tester.pump();
    final before = next.transfer.reads;
    await tester.pump(const Duration(milliseconds: 500));
    expect(next.transfer.reads, greaterThan(before));
    expect(first.deliveries, 0);
    expect(first.discards, 1);
    expect(old.transfer.cancelled, true);
    next.completion!.complete(
      const BhpanDownloadReceipt(bytes: 120, batch: false),
    );
    await tester.pumpAndSettle();
    expect(second.deliveries, 1);
  });
}
