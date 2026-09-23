import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';

void main() {
  test('恢复后的读取先于同级认证，但仍让位紧急任务', () async {
    final events = <String>[];
    final scheduler = ReadScheduler(canRun: (_) => true);
    final jobs = [
      scheduler.run(
        ReadPriority.home,
        () => true,
        () async => events.add('其他认证'),
      ),
      scheduler.run(
        ReadPriority.home,
        () => true,
        () async => events.add('已恢复读取'),
        continuation: true,
      ),
      scheduler.run(
        ReadPriority.urgent,
        () => true,
        () async => events.add('紧急读取'),
      ),
    ];
    await Future.wait(jobs);
    expect(events, ['紧急读取', '已恢复读取', '其他认证']);
    scheduler.close();
  });
  test('已发送批次收尾后，当前任务先于后续后台批次执行', () async {
    final events = <String>[];
    final gate = Completer<void>();
    final scheduler = ReadScheduler(canRun: (_) => true);
    final active = scheduler.run(ReadPriority.background, () => true, () async {
      events.add('在途批次');
      await gate.future;
    });
    await Future<void>.delayed(Duration.zero);
    final background = scheduler.run(
      ReadPriority.background,
      () => true,
      () async => events.add('后台下一批'),
    );
    final current = scheduler.run(
      ReadPriority.interactive,
      () => true,
      () async => events.add('签到当前读取'),
    );
    expect(events, ['在途批次']);
    gate.complete();
    await Future.wait([active, background, current]);
    expect(events, ['在途批次', '签到当前读取', '后台下一批']);
    scheduler.close();
  });
  test('写活动暂停普通读取但既定回读不被自身等待阻塞', () async {
    var writeBusy = true;
    final events = <String>[];
    final scheduler = ReadScheduler(
      canRun: (priority) =>
          !writeBusy || priority == ReadPriority.writeReadback,
    );
    final normal = scheduler.run(
      ReadPriority.interactive,
      () => true,
      () async => events.add('普通读取'),
    );
    final readback = scheduler.run(
      ReadPriority.writeReadback,
      () => true,
      () async => events.add('既定回读'),
    );
    await readback;
    expect(events, ['既定回读']);
    writeBusy = false;
    scheduler.pump();
    await normal;
    expect(events, ['既定回读', '普通读取']);
    scheduler.close();
  });
  test('账号代次失效时，未发批次取消且在途结果不可交付', () async {
    var current = true;
    final gate = Completer<int>();
    final scheduler = ReadScheduler(canRun: (_) => true);
    final active = scheduler.run(
      ReadPriority.home,
      () => current,
      () => gate.future,
    );
    final activeRejected = expectLater(active, throwsA(isA<ReadCancelled>()));
    await Future<void>.delayed(Duration.zero);
    final queued = scheduler.run(
      ReadPriority.home,
      () => current,
      () async => fail('失效批次不得开始'),
    );
    final queuedRejected = expectLater(queued, throwsA(isA<ReadCancelled>()));
    current = false;
    scheduler.pump();
    gate.complete(1);
    await Future.wait([activeRejected, queuedRejected]);
    scheduler.close();
  });
  test('可选调度诊断分别记录排队、执行等待和运行耗时', () async {
    final traces = <ReadSchedulerTrace>[];
    final scheduler = ReadScheduler(canRun: (_) => true, onTrace: traces.add);
    await scheduler.run(ReadPriority.home, () => true, () async {});
    expect(traces.map((trace) => trace.kind), [
      ReadSchedulerTraceKind.queued,
      ReadSchedulerTraceKind.started,
      ReadSchedulerTraceKind.completed,
    ]);
    expect(traces.last.waitUs, greaterThanOrEqualTo(0));
    expect(traces.last.runUs, greaterThanOrEqualTo(0));
    scheduler.close();
  });
}
