import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support.dart';
import 'support.dart';

const receivedFolder = BhpanItem(
  handle: 'received-folder',
  name: '分享目录',
  kind: BhpanItemKind.folder,
  scope: BhpanScope.receivedShare,
);

class ReceivedFolderFiles extends Files {
  @override
  Future<BhpanPage> read(BhpanRead query) async {
    if (query.view == BhpanReadView.receivedShare) {
      reads.add(query);
      return page([receivedFolder]);
    }
    if (query.target == receivedFolder.handle) {
      reads.add(query);
      return page([]);
    }
    return super.read(query);
  }
}

void main() {
  testWidgets('个人目录新增面板三项可用，并分别交付上传、新建和秒传参数', (tester) async {
    final requests = <BhpanMutation>[];
    final files = Files();
    const localFile = BhpanLocalFile(path: '/synthetic/notes', name: '笔记.txt');
    var picks = 0;
    await mountBhpan(
      tester,
      BhpanAccess(
        service: files,
        pickFile: () async {
          picks++;
          return localFile;
        },
        runWrite: (request) async {
          requests.add(request);
          return null;
        },
      ),
    );
    await openCreateSheet(tester);
    for (final action in ['上传文件', '新建文件夹', '秒传']) {
      expect(tester.widget<ListTile>(sheetAction(action)).enabled, isTrue);
    }
    await tester.tap(sheetAction('上传文件'));
    await tester.pumpAndSettle();
    await openCreateSheet(tester);
    await tester.tap(sheetAction('新建文件夹'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '实验笔记');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await openCreateSheet(tester);
    await tester.tap(sheetAction('秒传'));
    await tester.pumpAndSettle();
    expect(requests.map((request) => request.kind), [
      BhpanMutationKind.upload,
      BhpanMutationKind.createFolder,
      BhpanMutationKind.uploadFast,
    ]);
    expect(requests.map((request) => request.target), ['root', 'root', 'root']);
    expect(requests[1].name, '实验笔记');
    expect(picks, 2);
    for (final request in [requests.first, requests.last]) {
      expect(request.source, same(localFile));
      expect(request.transfer, isNotNull);
    }
    expect(requests.first.transfer, isNot(same(requests.last.transfer)));
  });

  testWidgets('接收分享的目录只提供普通上传，上传目标保持分享目录', (tester) async {
    final requests = <BhpanMutation>[];
    await mountBhpan(
      tester,
      BhpanAccess(
        service: ReceivedFolderFiles(),
        pickFile: () async =>
            const BhpanLocalFile(path: '/synthetic/share', name: '附件.txt'),
        runWrite: (request) async {
          requests.add(request);
          return null;
        },
      ),
    );
    await openCloudMenu(tester, '接收分享');
    await tester.enterText(
      find.widgetWithText(TextField, '北航云盘分享链接或标识'),
      'synthetic-share',
    );
    await tester.tap(find.text('打开分享'));
    await tester.pumpAndSettle();
    await openCreateSheet(tester);
    expect(tester.widget<ListTile>(sheetAction('上传文件')).enabled, isTrue);
    expect(sheetAction('新建文件夹'), findsNothing);
    expect(sheetAction('秒传'), findsNothing);
    await tester.tap(sheetAction('上传文件'));
    await tester.pumpAndSettle();
    expect(requests.single.kind, BhpanMutationKind.upload);
    expect(requests.single.target, receivedFolder.handle);
    expect(requests.single.source!.name, '附件.txt');
  });
}
