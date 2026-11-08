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
      BhpanAccess(
        service: files,
        runWrite: (_, [_ = const BhpanWriteStyle()]) async => null,
      ),
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
          .widget<InkWell>(find.byKey(const ValueKey('bhpan-batch-recycle')))
          .onTap,
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
    await tester.tap(find.text('取消全选'));
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
    ('restore', BhpanMutationKind.restore),
    ('deleteForever', BhpanMutationKind.deleteForever),
  ]) {
    testWidgets('回收站独立页面多选 ${action.$2.name} 依次交付每个句柄', (tester) async {
      final files = RecycleFiles();
      final requests = <BhpanMutation>[];
      await mountBhpan(
        tester,
        BhpanAccess(
          service: files,
          runWrite: (request, [_ = const BhpanWriteStyle()]) async {
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
      await openPlace(tester, '回收站');
      expect(find.text('仅显示最近 100 项'), findsOneWidget);
      expect(
        _topLayer(find.byKey(const ValueKey('bhpan-create'))),
        findsNothing,
      );
      await tester.longPress(_topLayer(find.text('课程资料')));
      await tester.pumpAndSettle();
      await tester.tap(_topLayer(find.text('全选')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);
      expect(find.byKey(const ValueKey('bhpan-batch-download')), findsNothing);
      await tester.tap(find.byKey(ValueKey('bhpan-batch-${action.$1}')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          action.$2 == BhpanMutationKind.restore ? '恢复' : '永久删除',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bhpan-batch-results')));
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

/// 宽屏子页面以对话框叠在云盘上，背景仍可见；只在最上层查找。
Finder _topLayer(Finder finder) => find.byType(Dialog).evaluate().isEmpty
    ? finder
    : find.descendant(of: find.byType(Dialog).last, matching: finder);
