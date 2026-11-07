import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/bhpan/sheets.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support.dart';
import 'support.dart';

void main() {
  testWidgets('文件更多操作：快捷操作在上，移入回收站以错误色置底并交付文件句柄', (tester) async {
    final requests = <BhpanMutation>[];
    await mountBhpan(
      tester,
      BhpanAccess(
        service: Files(),
        runWrite: (request, [_ = const BhpanWriteStyle()]) async {
          requests.add(request);
          return null;
        },
      ),
    );
    await openItemActions(tester, '报告.txt');
    const order = ['下载', '分享', '复制到', '详细信息', '分享记录', '移入回收站'];
    for (var index = 1; index < order.length; index++) {
      expect(
        tester.getTopLeft(sheetText(order[index])).dy,
        greaterThanOrEqualTo(tester.getTopLeft(sheetText(order[index - 1])).dy),
      );
    }
    // 快捷操作同一行。
    expect(
      tester.getTopLeft(sheetText('重命名')).dy,
      tester.getTopLeft(sheetText('下载')).dy,
    );
    final dangerText = sheetText('移入回收站');
    expect(
      tester.widget<Text>(dangerText).style!.color,
      Theme.of(tester.element(dangerText)).colorScheme.error,
    );
    await tester.tap(dangerText);
    await tester.pumpAndSettle();
    expect(requests.single.kind, BhpanMutationKind.recycle);
    expect(requests.single.target, 'file');
  });

  testWidgets('点文件打开详细信息，文件不统计内容，可从面板直接下载', (tester) async {
    final files = Files();
    var picks = 0;
    await mountBhpan(
      tester,
      BhpanAccess(
        service: files,
        pickDownload: (_, __) async {
          picks++;
          return null;
        },
      ),
    );
    await tester.tap(find.text('报告.txt'));
    await tester.pumpAndSettle();
    expect(sheetText('文本'), findsOneWidget);
    expect(find.text('120 B'), findsWidgets);
    expect(sheetText('个人文档库'), findsOneWidget);
    expect(find.textContaining('个文件夹、'), findsNothing);
    await tester.tap(sheetText('下载'));
    await tester.pumpAndSettle();
    expect(picks, 1);
  });

  testWidgets('文件夹详细信息异步统计包含的内容', (tester) async {
    await mountBhpan(tester, BhpanAccess(service: Files()));
    await openItemActions(tester, '课程资料');
    await tester.tap(sheetText('详细信息'));
    await tester.pumpAndSettle();
    expect(sheetText('1 个文件夹、1 个文件，共 120 B'), findsOneWidget);
  });

  testWidgets('通用面板把危险操作集中置底，并返回选中的操作', (tester) async {
    BhpanAction? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await bhpanActionSheet(
                  context,
                  item: file,
                  actions: const [
                    BhpanAction.deleteForever,
                    BhpanAction.details,
                    BhpanAction.restore,
                  ],
                  enabled: (_) => true,
                );
              },
              child: const Text('打开操作'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开操作'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(sheetText('永久删除')).dy,
      greaterThan(tester.getTopLeft(sheetText('恢复')).dy),
    );
    await tester.tap(sheetText('永久删除'));
    await tester.pumpAndSettle();
    expect(selected, BhpanAction.deleteForever);
  });
}
