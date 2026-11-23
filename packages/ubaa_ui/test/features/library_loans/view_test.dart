import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/library_loans/view.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';

LibraryLoan loan({
  String id = 'loan-1',
  String title = '合成书目',
  String? author = '合成作者',
  String? loanDate = '2026-11-01',
  String? dueDate = '2026-12-01',
  int? renewTimes = 1,
  int? canRenewTimes = 2,
  LibraryLoanStatus status = LibraryLoanStatus.soon,
}) => LibraryLoan(
  id: id,
  title: title,
  author: author,
  loanDate: loanDate,
  dueDate: dueDate,
  renewTimes: renewTimes,
  canRenewTimes: canRenewTimes,
  status: status,
  location: '合成馆藏地',
);

Future<void> pump(
  WidgetTester tester, {
  required LibraryLoansReader read,
  LibraryLoanRenewStarter? renew,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: LibraryLoansView(read: read, renew: renew),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _LoanReader {
  int calls = 0;

  Future<List<LibraryLoan>> read() async {
    calls++;
    return [loan()];
  }
}

void main() {
  testWidgets('展示书名、作者、日期、续借次数和状态', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 17, 9)), () async {
      await pump(tester, read: () async => [loan()]);
      expect(find.text('合成书目'), findsOneWidget);
      expect(find.text('合成作者'), findsOneWidget);
      expect(find.text('即将到期'), findsOneWidget);
      expect(find.textContaining('12月1日'), findsOneWidget);
      expect(find.text('续借 1 次'), findsOneWidget);
      expect(find.text('可续借 2 次'), findsOneWidget);
      expect(find.text('馆藏地  合成馆藏地'), findsOneWidget);
      expect(find.text('共 1 本在借'), findsOneWidget);
    });
  });

  testWidgets('空列表显示固定空状态', (tester) async {
    await pump(tester, read: () async => const []);
    expect(find.text('暂无待还图书'), findsOneWidget);
  });

  testWidgets('读取失败提供重试并恢复列表', (tester) async {
    var calls = 0;
    await pump(
      tester,
      read: () async {
        calls++;
        if (calls == 1) {
          throw const UiError(
            code: UbaaErrorCode.upstreamUnavailable,
            title: '读取失败',
            message: '合成读取失败',
          );
        }
        return [loan()];
      },
    );
    expect(find.text('借阅记录读取失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('合成书目'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('续借成功后重新读取并更新应还日期和次数', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 17, 9)), () async {
      var current = loan();
      String? renewed;
      final outcome = WriteOutcome(
        operation: WriteOperation.libraryLoanRenew,
        message: '续借成功',
        result: const WriteCommitResult(
          operation: WriteOperation.libraryLoanRenew,
          success: true,
          message: '续借成功',
          outcomeUnknown: false,
          resolvedRoute: ConnectionMode.direct,
        ),
      );
      await pump(
        tester,
        read: () async => [current],
        renew: (selected) async {
          renewed = selected;
          current = loan(
            dueDate: '2027-01-05',
            renewTimes: 2,
            canRenewTimes: 1,
          );
          return WriteOutcome(
            operation: WriteOperation.libraryLoanRenew,
            message: outcome.message,
            result: outcome.result,
            libraryLoanRenewReadback: LibraryLoanRenewReadback(
              loanId: selected,
              loans: [current],
              route: ConnectionMode.direct,
              status: LibraryRenewStatus.applied,
            ),
          );
        },
      );
      await tester.tap(find.widgetWithText(FilledButton, '续借'));
      await tester.pumpAndSettle();
      expect(renewed, 'loan-1');
      expect(find.textContaining('1月5日'), findsWidgets);
      expect(find.text('续借 2 次'), findsOneWidget);
      expect(find.text('可续借 1 次'), findsOneWidget);
      expect(find.textContaining('续借成功'), findsWidgets);
    });
  });

  testWidgets('结果未知时只读核对已变化的记录并提示成功', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 17, 9)), () async {
      var current = loan();
      await pump(
        tester,
        read: () async => [current],
        renew: (selected) async {
          current = loan(dueDate: '2027-01-05', renewTimes: 2);
          return WriteOutcome(
            operation: WriteOperation.libraryLoanRenew,
            message: '结果未确认，请刷新后查看，勿重复提交',
            result: const WriteCommitResult(
              operation: WriteOperation.libraryLoanRenew,
              success: false,
              message: '结果未确认',
              outcomeUnknown: true,
              resolvedRoute: ConnectionMode.direct,
            ),
            libraryLoanRenewReadback: LibraryLoanRenewReadback(
              loanId: selected,
              loans: [current],
              route: ConnectionMode.direct,
              status: LibraryRenewStatus.applied,
            ),
          );
        },
      );
      await tester.tap(find.widgetWithText(FilledButton, '续借'));
      await tester.pumpAndSettle();
      expect(find.textContaining('续借成功'), findsWidgets);
      expect(find.textContaining('勿重复提交'), findsNothing);
    });
  });

  testWidgets('结果未知且记录未变化时不升级为成功', (tester) async {
    await pump(
      tester,
      read: () async => [loan()],
      renew: (selected) async => WriteOutcome(
        operation: WriteOperation.libraryLoanRenew,
        message: '结果未确认，请刷新后查看，勿重复提交',
        result: const WriteCommitResult(
          operation: WriteOperation.libraryLoanRenew,
          success: false,
          message: '结果未确认',
          outcomeUnknown: true,
          resolvedRoute: ConnectionMode.direct,
        ),
        libraryLoanRenewReadback: LibraryLoanRenewReadback(
          loanId: selected,
          loans: [loan()],
          route: ConnectionMode.direct,
          status: LibraryRenewStatus.unchanged,
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '续借'));
    await tester.pumpAndSettle();
    expect(find.textContaining('续借未生效'), findsOneWidget);
    expect(find.textContaining('勿重复提交'), findsNothing);
  });

  testWidgets('待核对记录禁用续借并单独提供只读核对', (tester) async {
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryLoansView(
            read: () async => [loan()],
            pending: const {'loan-1'},
            renew: (_) => throw StateError('不得提交'),
            recheck: (_) async {
              checks++;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '续借'), findsNothing);
    expect(find.text('待核对'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '核对'));
    await tester.pumpAndSettle();
    expect(checks, 1);
  });

  testWidgets('续借核对替换在途的普通刷新，迟到数据不覆盖核对结果', (tester) async {
    final stale = Completer<List<LibraryLoan>>();
    final fresh = Completer<List<LibraryLoan>>();
    final pendingRenewal = Completer<WriteOutcome>();
    var reads = 0;
    await pump(
      tester,
      read: () async => switch (++reads) {
        1 => [loan()],
        2 => await stale.future,
        _ => await fresh.future,
      },
      renew: (_) => pendingRenewal.future,
    );
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    expect(reads, 2);
    await tester.tap(find.widgetWithText(FilledButton, '续借'));
    await tester.pump();
    pendingRenewal.complete(
      WriteOutcome(
        operation: WriteOperation.libraryLoanRenew,
        message: '续借成功',
        result: const WriteCommitResult(
          operation: WriteOperation.libraryLoanRenew,
          success: true,
          message: '续借成功',
          outcomeUnknown: false,
          resolvedRoute: ConnectionMode.direct,
        ),
        libraryLoanRenewReadback: LibraryLoanRenewReadback(
          loanId: 'loan-1',
          loans: [loan(renewTimes: 2)],
          route: ConnectionMode.direct,
          status: LibraryRenewStatus.applied,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('续借 2 次'), findsOneWidget);

    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    expect(reads, 3);
    stale.complete([loan()]);
    await tester.pump();
    expect(find.text('续借 2 次'), findsOneWidget);
    final refresh = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '刷新',
    );
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    fresh.complete([loan(renewTimes: 3)]);
    await tester.pumpAndSettle();
    expect(find.text('续借 3 次'), findsOneWidget);
  });

  testWidgets('宿主重建后同一读取回调保留在途的续借核对', (tester) async {
    final reader = _LoanReader();
    final pendingRenewal = Completer<WriteOutcome>();
    await pump(tester, read: reader.read, renew: (_) => pendingRenewal.future);
    await tester.tap(find.widgetWithText(FilledButton, '续借'));
    await tester.pump();

    await pump(tester, read: reader.read, renew: (_) => pendingRenewal.future);
    expect(reader.calls, 1);
    pendingRenewal.complete(
      WriteOutcome(
        operation: WriteOperation.libraryLoanRenew,
        message: '续借成功',
        result: const WriteCommitResult(
          operation: WriteOperation.libraryLoanRenew,
          success: true,
          message: '续借成功',
          outcomeUnknown: false,
          resolvedRoute: ConnectionMode.direct,
        ),
        libraryLoanRenewReadback: LibraryLoanRenewReadback(
          loanId: 'loan-1',
          loans: [loan(renewTimes: 2)],
          route: ConnectionMode.direct,
          status: LibraryRenewStatus.applied,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('续借 2 次'), findsOneWidget);
  });

  testWidgets('不可续借时按钮禁用', (tester) async {
    await pump(
      tester,
      read: () async => [loan(renewTimes: 3, canRenewTimes: 0)],
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '续借'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('不可续借'), findsOneWidget);
  });
}
