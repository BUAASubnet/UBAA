import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support.dart';

Future<void> mount(
  WidgetTester tester,
  Files files, {
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
}

void main() {
  testWidgets('个人目录自动打开，当前名称筛选和面包屑返回保留可用目录', (tester) async {
    final files = Files();
    await mount(tester, files, run: (_) async => null);
    expect(find.text('报告.txt'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '课程');
    await tester.pump();
    expect(find.text('报告.txt'), findsNothing);
    expect(find.text('课程资料'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('课程资料'));
    await tester.pumpAndSettle();
    expect(find.text('当前已读取范围没有条目'), findsOneWidget);
    await tester.tap(find.text('› 个人文档库'));
    await tester.pumpAndSettle();
    expect(find.text('报告.txt'), findsOneWidget);
    expect(files.reads.last.target, 'root');
  });
  testWidgets('新建操作只交付用户输入的父目录句柄与名称', (tester) async {
    final files = Files();
    BhpanMutation? request;
    await mount(
      tester,
      files,
      run: (value) async {
        request = value;
        return null;
      },
    );
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '名称'), '实验材料');
    await tester.tap(find.text('继续'));
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
      run: (value) async {
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
    await tester.tap(find.text('逐项移入回收站'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.target), ['folder']);
    expect(find.text('提交结果不确定，请先刷新核对'), findsOneWidget);
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
    expect(find.text('当前已读取范围没有条目'), findsOneWidget);
  });
  testWidgets('账号服务替换关闭旧账号已经打开的编辑弹窗', (tester) async {
    final old = Files();
    await mount(tester, old, run: (_) async => null);
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹'), findsOneWidget);
    final next = Files()..contents = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: Scaffold(
          body: BhpanView(
            access: BhpanAccess(service: next, runWrite: (_) async => null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹'), findsNothing);
  });
}
