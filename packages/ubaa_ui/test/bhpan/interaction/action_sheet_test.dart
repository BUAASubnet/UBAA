import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/bhpan/chrome.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support.dart';
import 'support.dart';

void main() {
  testWidgets('文件更多操作在底部列出操作，移入回收站位于最后并交付文件句柄', (tester) async {
    final requests = <BhpanMutation>[];
    await mountBhpan(
      tester,
      BhpanAccess(
        service: Files(),
        runWrite: (request) async {
          requests.add(request);
          return null;
        },
      ),
    );
    await openItemActions(tester, '报告.txt');
    const actions = ['属性', '重命名', '移动', '复制', '下载', '分享', '分享记录', '移入回收站'];
    for (var index = 1; index < actions.length; index++) {
      expect(
        tester.getTopLeft(sheetAction(actions[index])).dy,
        greaterThan(tester.getTopLeft(sheetAction(actions[index - 1])).dy),
      );
    }
    final dangerText = find.descendant(
      of: sheetAction('移入回收站'),
      matching: find.text('移入回收站'),
    );
    expect(
      tester.widget<Text>(dangerText).style!.color,
      Theme.of(tester.element(dangerText)).colorScheme.error,
    );
    await tester.tap(sheetAction('移入回收站'));
    await tester.pumpAndSettle();
    expect(requests.single.kind, BhpanMutationKind.recycle);
    expect(requests.single.target, 'file');
  });

  testWidgets('底部面板将混入普通操作的危险项集中置底，并返回选中的操作', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await bhpanActionSheet(
                  context,
                  title: '批量操作',
                  item: null,
                  actions: ['永久删除', '属性', '移入回收站', '下载'],
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
    for (final danger in ['永久删除', '移入回收站']) {
      expect(
        tester.getTopLeft(sheetAction(danger)).dy,
        greaterThan(tester.getTopLeft(sheetAction('下载')).dy),
      );
    }
    await tester.tap(sheetAction('永久删除'));
    await tester.pumpAndSettle();
    expect(selected, '永久删除');
  });
}
