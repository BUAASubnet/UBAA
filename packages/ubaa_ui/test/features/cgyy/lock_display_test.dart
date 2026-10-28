import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

class _Session implements CgyyLockDisplaySession {
  final events = StreamController<void>.broadcast(sync: true);
  final requests = <Completer<CgyyLockDisplay>>[];
  bool closed = false;
  @override
  Stream<void> get cancelled => events.stream;
  @override
  Future<CgyyLockDisplay> read() {
    final c = Completer<CgyyLockDisplay>();
    requests.add(c);
    return c.future;
  }

  @override
  void cancel() {
    if (closed) return;
    closed = true;
    events.add(null);
    unawaited(events.close());
  }
}

Widget _view(_Session session, {bool visible = true}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: UbaaCgyyLockDisplayView(open: () async => session, visible: visible),
  ),
);
void main() {
  testWidgets('门锁显示30秒到期先清旧码且手动定时单飞', (tester) async {
    final session = _Session();
    await tester.pumpWidget(_view(session));
    await tester.pump();
    expect(session.requests, hasLength(1));
    session.requests[0].complete(
      CgyyLockDisplay(
        code: '001234',
        dueDate: '上游时间原文',
        reservationReference: 'synthetic-reference',
        spaceName: '合成室',
        reservationDateDetail: '合成室 / 08:00-09:00',
      ),
    );
    await tester.pump();
    expect(find.text('001234'), findsOneWidget);
    expect(find.text('08:00-09:00'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 29999));
    expect(session.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('001234'), findsNothing);
    expect(session.requests, hasLength(2));
    await tester.tap(find.byTooltip('刷新密码'));
    await tester.pump();
    expect(session.requests, hasLength(2));
    session.requests[1].completeError(StateError('synthetic-sensitive-error'));
    await tester.pump();
    expect(find.text('001234'), findsNothing);
    expect(find.textContaining('synthetic-sensitive-error'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(session.closed, isTrue);
  });
  testWidgets('门锁隐藏取消晚到结果不得复活并释放材料', (tester) async {
    final session = _Session();
    await tester.pumpWidget(_view(session));
    await tester.pump();
    expect(session.requests, hasLength(1));
    await tester.pumpWidget(_view(session, visible: false));
    expect(session.closed, isTrue);
    final late = CgyyLockDisplay(code: 'late-secret');
    session.requests.single.complete(late);
    await tester.pump();
    expect(find.text('late-secret'), findsNothing);
    expect(late.code, isNull);
  });
  testWidgets('门锁会话被账号路线变更撤销后立即清显示', (tester) async {
    final session = _Session();
    await tester.pumpWidget(_view(session));
    await tester.pump();
    expect(session.requests, hasLength(1));
    final value = CgyyLockDisplay(code: '001234');
    session.requests.single.complete(value);
    await tester.pump();
    session.cancel();
    await tester.pump();
    expect(find.text('001234'), findsNothing);
    expect(value.code, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
