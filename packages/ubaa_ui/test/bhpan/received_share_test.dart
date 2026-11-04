import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support.dart';

const received = BhpanItem(
  handle: 'received-file',
  name: '分享文件.txt',
  kind: BhpanItemKind.file,
  scope: BhpanScope.receivedShare,
  bytes: 120,
);

class ReceivedFiles extends Files {
  bool denied = false;
  @override
  Future<BhpanPage> read(BhpanRead query) async {
    if (query.view == BhpanReadView.receivedShare) {
      reads.add(query);
      if (denied) {
        throw const UiError(
          code: UbaaErrorCode.permissionDenied,
          title: '分享授权不可用',
          message: '分享授权不可用，请检查密码、有效期和权限',
        );
      }
      return page([received]);
    }
    return super.read(query);
  }
}

Future<void> openReceived(
  WidgetTester tester,
  ReceivedFiles files, {
  Future<WriteOutcome?> Function(BhpanMutation)? run,
}) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: Scaffold(
        body: BhpanView(
          access: BhpanAccess(service: files, runWrite: run),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('接收分享'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, '北航云盘分享链接或标识'),
    'fixture-share',
  );
  await tester.enterText(
    find.widgetWithText(TextField, '提取密码（如有）'),
    'fixture-password',
  );
  await tester.tap(find.text('打开分享'));
  await tester.pumpAndSettle();
  expect(find.text('分享文件.txt'), findsOneWidget);
}

void main() {
  testWidgets('单文件分享刷新保留来源，明确切库后读取个人目录', (tester) async {
    final files = ReceivedFiles();
    await openReceived(tester, files);
    final start = files.reads.length;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('分享文件.txt'), findsOneWidget);
    expect(find.text('报告.txt'), findsNothing);
    expect(files.reads.skip(start).map((q) => q.view), [
      BhpanReadView.receivedShare,
    ]);
    expect(files.reads.last.link, 'fixture-share');
    expect(files.reads.last.password, 'fixture-password');
    final switching = files.reads.length;
    await tester.tap(find.text('文档库 ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人文档库'));
    await tester.pumpAndSettle();
    expect(files.reads.skip(switching).map((q) => q.view), [
      BhpanReadView.personalRoot,
      BhpanReadView.directory,
    ]);
    expect(find.text('报告.txt'), findsOneWidget);
    expect(find.text('分享文件.txt'), findsNothing);
  });

  testWidgets('单文件分享另存后回读分享，个人目录只用于选择目的地', (tester) async {
    final files = ReceivedFiles();
    final mutations = <BhpanMutation>[];
    await openReceived(
      tester,
      files,
      run: (request) async {
        mutations.add(request);
        return const WriteOutcome(
          operation: WriteOperation.bhpan,
          message: '已另存',
          result: WriteCommitResult(
            operation: WriteOperation.bhpan,
            success: true,
            outcomeUnknown: false,
            message: '已另存',
          ),
        );
      },
    );
    final start = files.reads.length;
    final row = find.ancestor(
      of: find.text('分享文件.txt'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('另存到网盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('个人文档库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择此目录'));
    await tester.pumpAndSettle();
    expect(mutations.single.kind, BhpanMutationKind.copy);
    expect(mutations.single.target, 'received-file');
    expect(mutations.single.destination, 'root');
    expect(files.reads.skip(start).map((q) => q.view), [
      BhpanReadView.personalRoot,
      BhpanReadView.directory,
      BhpanReadView.receivedShare,
    ]);
    expect(find.text('分享文件.txt'), findsOneWidget);
    expect(find.text('报告.txt'), findsNothing);
  });

  testWidgets('分享重新授权失败明确提示并保留分享读取条件', (tester) async {
    final files = ReceivedFiles();
    await openReceived(tester, files);
    files.denied = true;
    final start = files.reads.length;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('分享授权不可用，请检查密码、有效期和权限'), findsOneWidget);
    expect(find.text('报告.txt'), findsNothing);
    expect(files.reads.skip(start).map((q) => q.view), [
      BhpanReadView.receivedShare,
    ]);
    expect(find.text('接收分享'), findsOneWidget);
  });
}
