import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support.dart';
import 'support.dart';

class RecycleFiles extends Files {
  @override
  Future<BhpanPage> read(BhpanRead query) async {
    if (query.view != BhpanReadView.recycle) return super.read(query);
    reads.add(query);
    return BhpanPage(
      items: [
        for (final item in [folder, file])
          BhpanItem(
            handle: 'deleted-${item.handle}',
            name: item.name,
            kind: item.kind,
            scope: BhpanScope.recycle,
          ),
      ],
      range: BhpanListRange.firstHundred,
      route: ConnectionMode.direct,
      fetchedAt: DateTime.utc(2026, 11, 5),
    );
  }
}

void main() {
  testWidgets('长按选择后点按只切换选中项，全选和取消恢复普通浏览', (tester) async {
    final files = Files();
    await mountBhpan(
      tester,
      BhpanAccess(service: files, runWrite: (_) async => null),
    );
    final reads = files.reads.length;
    expect(find.byType(Checkbox), findsNothing);
    await tester.longPress(find.text('课程资料'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: itemRow('课程资料'),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '逐项移入回收站',
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('报告.txt'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
    await tester.tap(find.text('课程资料'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: itemRow('课程资料'),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isFalse,
    );
    expect(files.reads.length, reads);
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消选择'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    await tester.longPress(find.text('报告.txt'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程资料'));
    await tester.pumpAndSettle();
    expect(files.reads.last.target, 'folder');
    expect(find.text('这个文件夹是空的'), findsOneWidget);
  });

  for (final action in [
    ('逐项恢复', BhpanMutationKind.restore),
    ('逐项永久删除', BhpanMutationKind.deleteForever),
  ]) {
    testWidgets('回收站多选通过底部${action.$1}依次交付每个句柄', (tester) async {
      final files = RecycleFiles();
      final requests = <BhpanMutation>[];
      await mountBhpan(
        tester,
        BhpanAccess(
          service: files,
          runWrite: (request) async {
            requests.add(request);
            return const WriteOutcome(
              operation: WriteOperation.bhpan,
              message: '已完成',
              result: WriteCommitResult(
                operation: WriteOperation.bhpan,
                success: true,
                outcomeUnknown: false,
                message: '已完成',
              ),
            );
          },
        ),
      );
      await openCloudMenu(tester, '回收站');
      expect(find.text('回收站仅显示前 100 项'), findsOneWidget);
      expect(find.byKey(const ValueKey('bhpan-create')), findsNothing);
      await tester.longPress(find.text('课程资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);
      expect(find.byTooltip('打包下载'), findsNothing);
      await tester.tap(find.byTooltip(action.$1));
      await tester.pumpAndSettle();
      expect(requests.map((request) => request.kind), [action.$2, action.$2]);
      expect(requests.map((request) => request.target), [
        'deleted-folder',
        'deleted-file',
      ]);
      expect(find.text('课程资料：已完成'), findsOneWidget);
      expect(find.text('报告.txt：已完成'), findsOneWidget);
    });
  }
}
