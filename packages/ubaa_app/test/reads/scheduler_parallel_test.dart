import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'progressive_test.dart' show until;

void main() {
  test('同级认证先集中完成，再并行启动已恢复的业务', () async {
    final scheduler = ReadScheduler(canRun: (_) => true);
    addTearDown(scheduler.close);
    final events = <String>[];
    final read = scheduler.run(
      ReadPriority.home,
      () => true,
      () async => events.add('读取'),
      lane: ReadLane.signin,
      continuation: true,
    );
    final auth = scheduler.run(
      ReadPriority.home,
      () => true,
      () async => events.add('认证'),
    );
    await Future.wait([read, auth]);
    expect(events, ['认证', '读取']);
  });
  test('最多八个业务在途，同组等待且独占写回读优先排空队列', () async {
    final scheduler = ReadScheduler(canRun: (_) => true);
    addTearDown(scheduler.close);
    final gates = List.generate(8, (_) => Completer<void>());
    addTearDown(() {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    final started = <String>[];
    final lanes = ReadLane.values;
    final jobs = [
      for (var i = 0; i < lanes.length; i++)
        scheduler.run(ReadPriority.home, () => true, () async {
          started.add(lanes[i].name);
          await gates[i].future;
        }, lane: lanes[i]),
    ];
    await until(() => started.length == 8);
    final same = scheduler.run(
      ReadPriority.home,
      () => true,
      () async => started.add('同组'),
      lane: ReadLane.academic,
    );
    final write = scheduler.run(
      ReadPriority.writeReadback,
      () => true,
      () async => started.add('写回读'),
    );
    gates[0].complete();
    await jobs[0];
    await Future<void>.delayed(Duration.zero);
    expect(started.length, 8, reason: '空出的名额必须留待独占任务，不能继续发读取');
    for (var i = 1; i < 8; i++) {
      gates[i].complete();
    }
    await write;
    expect(started.indexOf('写回读'), 8);
    await Future.wait([...jobs, same]);
    expect(started.indexOf('同组'), greaterThan(started.indexOf('写回读')));
  });
}
