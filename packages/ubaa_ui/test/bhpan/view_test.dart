import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/bhpan/location.dart';
import 'package:ubaa_ui/src/features/bhpan/view.dart' show BhpanBackHandle;
import 'package:ubaa_ui/src/features/bhpan/sheets.dart';
import 'interaction/support.dart';
import 'support.dart';

class MoveFiles extends Files {
  @override
  Future<BhpanPage> read(BhpanRead query) async {
    reads.add(query);
    if (query.view == BhpanReadView.personalRoot) return page([root]);
    if (query.target == 'folder') return page([file]);
    return page([folder, file]);
  }
}

Future<void> mount(
  WidgetTester tester,
  Files files, {
  Future<WriteOutcome?> Function(BhpanMutation, [BhpanWriteStyle])? run,
  BhpanBackHandle? back,
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
          backHandle: back,
          access: BhpanAccess(service: files, runWrite: run),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openNewFolder(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('bhpan-create')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('新建文件夹'));
  await tester.pumpAndSettle();
}

Finder pathText(String name) =>
    find.descendant(of: find.byType(BhpanLocationBar), matching: find.text(name));

void main() {
  testWidgets('个人目录自动打开，搜索只筛选当前目录，返回逐级回到上一层', (tester) async {
    final files = Files();
    final back = BhpanBackHandle();
    await mount(tester, files, run: (_, [_ = const BhpanWriteStyle()]) async => null, back: back);
    expect(find.text('报告.txt'), findsOneWidget);
    // 自动进入的个人根目录不出现在路径里。
    expect(pathText('个人文档库'), findsOneWidget);
    expect(back.handleBack(), isFalse);
    final readsBeforeFilter = files.reads.length;
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byType(SearchBar),
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<SearchBar>(find.byType(SearchBar)).hintText,
      '在此文件夹中搜索',
    );
    await tester.enterText(search, '课程');
    await tester.pump();
    expect(find.text('报告.txt'), findsNothing);
    expect(find.text('课程资料'), findsOneWidget);
    expect(files.reads.length, readsBeforeFilter);
    // 第一次返回先关闭搜索，不离开目录。
    expect(back.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsNothing);
    expect(find.text('报告.txt'), findsOneWidget);
    await tester.tap(find.text('课程资料'));
    await tester.pumpAndSettle();
    expect(files.reads.last.target, 'folder');
    expect(find.text('这个文件夹是空的'), findsOneWidget);
    expect(pathText('课程资料'), findsOneWidget);
    expect(back.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(files.reads.last.target, 'root');
    expect(find.text('报告.txt'), findsOneWidget);
    expect(pathText('课程资料'), findsNothing);
    expect(back.handleBack(), isFalse);
  });
  testWidgets('新建操作只交付用户输入的父目录句柄与名称', (tester) async {
    final files = Files();
    BhpanMutation? request;
    await mount(
      tester,
      files,
      run: (value, [_ = const BhpanWriteStyle()]) async {
        request = value;
        return null;
      },
    );
    await openNewFolder(tester);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '实验材料');
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(request!.kind, BhpanMutationKind.createFolder);
    expect(request!.target, 'root');
    expect(request!.name, '实验材料');
  });
  testWidgets('批量操作遇到结果未知停止后续提交并保留核对提示', (tester) async {
    final files = Files();
    final requests = <BhpanMutation>[];
    await mount(
      tester,
      files,
      run: (value, [_ = const BhpanWriteStyle()]) async {
        requests.add(value);
        return const WriteOutcome(
          operation: WriteOperation.bhpan,
          message: '提交结果不确定，请先刷新核对',
          error: UiError(
            code: UbaaErrorCode.outcomeUnknown,
            title: '结果待核对',
            message: '请勿重复提交',
          ),
        );
      },
    );
    await tester.longPress(find.text('课程资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('报告.txt'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bhpan-batch-recycle')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '移入回收站'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.target), ['folder']);
    expect(requests.single.kind, BhpanMutationKind.recycle);
    expect(find.text('提交结果不确定，请先刷新核对'), findsOneWidget);
    expect(find.text('课程资料：结果待核对'), findsOneWidget);
    expect(find.text('报告.txt：尚未执行'), findsOneWidget);
  });
  testWidgets('移动目标页排除自身并禁用原目录', (tester) async {
    await mount(
      tester,
      MoveFiles(),
      run: (_, [_ = const BhpanWriteStyle()]) async => null,
    );
    await tester.tap(find.text('课程资料'));
    await tester.pumpAndSettle();
    await openItemActions(tester, '报告.txt');
    await tester.tap(sheetText('移动'));
    await tester.pumpAndSettle();
    expect(find.text('报告.txt'), findsNothing);
    final pick = find.widgetWithText(FilledButton, '移动到此处');
    expect(pick, findsOneWidget);
    expect(tester.widget<FilledButton>(pick).onPressed, isNull);
  });
  testWidgets('账号服务替换后迟到目录不能进入新账号页面', (tester) async {
    final old = Files()..gate = Completer<BhpanPage>();
    final next = Files()..contents = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BhpanView(access: BhpanAccess(service: old)),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BhpanView(access: BhpanAccess(service: next)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    old.gate!.complete(page([file]));
    await tester.pumpAndSettle();
    expect(find.text('报告.txt'), findsNothing);
    expect(find.text('这个文件夹是空的'), findsOneWidget);
  });
  testWidgets('账号服务替换关闭旧账号已经打开的编辑弹窗', (tester) async {
    final old = Files();
    await mount(tester, old, run: (_, [_ = const BhpanWriteStyle()]) async => null);
    await openNewFolder(tester);
    expect(find.text('新建文件夹'), findsOneWidget);
    final next = Files()..contents = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: Scaffold(
          body: BhpanView(
            access: BhpanAccess(service: next, runWrite: (_, [_ = const BhpanWriteStyle()]) async => null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹'), findsNothing);
  });
}
