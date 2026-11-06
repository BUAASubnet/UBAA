import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support.dart';
import 'support.dart';

const sharedFolder = BhpanItem(
  handle: 'shared-root',
  name: '共享目录',
  kind: BhpanItemKind.folder,
  scope: BhpanScope.personal,
);

class SharedFiles extends Files {
  @override
  Future<BhpanPage> read(BhpanRead query) async {
    reads.add(query);
    if (query.view == BhpanReadView.roots &&
        query.root == BhpanRootKind.shared) {
      return page([sharedFolder]);
    }
    if (query.target == sharedFolder.handle) return page([]);
    return super.read(query);
  }
}

Future<void> openCreateMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('bhpan-create')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('個人文档库上传先尝试秒传，blocked 后只提交一次普通上传', (tester) async {
    final requests = <BhpanMutation>[];
    final styles = <BhpanWriteStyle>[];
    const source = BhpanLocalFile(path: '/synthetic/notes', name: '笔记.txt');
    await mountBhpan(
      tester,
      BhpanAccess(
        service: Files(),
        pickFile: () async => source,
        runWrite: (request, [style = const BhpanWriteStyle()]) async {
          requests.add(request);
          styles.add(style);
          if (request.kind == BhpanMutationKind.uploadFast) {
            (request.transfer as Transfer).phase = BhpanTransferPhase.blocked;
            throw const UiError(
              code: UbaaErrorCode.operationConflict,
              title: '不支持秒传',
              message: '改为普通上传',
            );
          }
          return null;
        },
      ),
    );
    await openCreateMenu(tester);
    expect(find.byKey(const ValueKey('bhpan-create-upload')), findsOneWidget);
    expect(find.byKey(const ValueKey('bhpan-create-folder')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bhpan-create-upload')));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.kind), [
      BhpanMutationKind.uploadFast,
      BhpanMutationKind.upload,
    ]);
    expect(requests.every((r) => r.source == source), isTrue);
    expect(requests.every((r) => r.target == 'root'), isTrue);
    expect(requests[0].transfer, isNot(same(requests[1].transfer)));
    expect(styles[1].note, contains('云端没有相同的文件'));
    expect(find.text('上传文件'), findsNothing);
  });

  testWidgets('秒传确认取消后不发起普通上传', (tester) async {
    final requests = <BhpanMutation>[];
    await mountBhpan(
      tester,
      BhpanAccess(
        service: Files(),
        pickFile: () async =>
            const BhpanLocalFile(path: '/synthetic/notes', name: '笔记.txt'),
        runWrite: (request, [_ = const BhpanWriteStyle()]) async {
          requests.add(request);
          return null;
        },
      ),
    );
    await openCreateMenu(tester);
    await tester.tap(find.byKey(const ValueKey('bhpan-create-upload')));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.kind), [BhpanMutationKind.uploadFast]);
  });

  testWidgets('共享文档库仍显示上传和新建文件夹，上传不尝试秒传', (tester) async {
    final requests = <BhpanMutation>[];
    await mountBhpan(
      tester,
      BhpanAccess(
        service: SharedFiles(),
        pickFile: () async =>
            const BhpanLocalFile(path: '/synthetic/share', name: '附件.txt'),
        runWrite: (request, [_ = const BhpanWriteStyle()]) async {
          requests.add(request);
          return null;
        },
      ),
    );
    await openPlace(tester, '共享文档库');
    await tester.tap(find.text('共享目录'));
    await tester.pumpAndSettle();
    await openCreateMenu(tester);
    expect(find.byKey(const ValueKey('bhpan-create-upload')), findsOneWidget);
    expect(find.byKey(const ValueKey('bhpan-create-folder')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bhpan-create-upload')));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.kind), [BhpanMutationKind.upload]);
    expect(requests.single.target, sharedFolder.handle);
  });

  testWidgets('共享文档库的新建文件夹交付当前目录和已确认样式', (tester) async {
    final requests = <BhpanMutation>[];
    final styles = <BhpanWriteStyle>[];
    await mountBhpan(
      tester,
      BhpanAccess(
        service: SharedFiles(),
        runWrite: (request, [style = const BhpanWriteStyle()]) async {
          requests.add(request);
          styles.add(style);
          return null;
        },
      ),
    );
    await openPlace(tester, '共享文档库');
    await tester.tap(find.text('共享目录'));
    await tester.pumpAndSettle();
    await openCreateMenu(tester);
    await tester.tap(find.byKey(const ValueKey('bhpan-create-folder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '实验材料');
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(requests.single.kind, BhpanMutationKind.createFolder);
    expect(requests.single.target, sharedFolder.handle);
    expect(requests.single.name, '实验材料');
    expect(styles.single.confirmed, isTrue);
  });
}
