import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_host/src/network_monitor.dart';

void main() {
  test('系统事件去重，离线不唤醒，恢复唤醒且没有周期轮询', () {
    fakeAsync((time) {
      final events = StreamController<Set<String>>.broadcast();
      var reads = 0, hints = 0;
      final monitor = LocalNetworkMonitor(
        readState: () async {
          reads++;
          return {};
        },
        events: events.stream,
      );
      final subscription = monitor.changes.listen((_) => hints++);
      time.flushMicrotasks();
      for (final state in [
        <String>{'wifi'},
        {'wifi'},
        <String>{},
        {'mobile'},
      ]) {
        events.add(state);
        time.flushMicrotasks();
      }
      expect(hints, 2);
      time.elapse(const Duration(minutes: 1));
      time.flushMicrotasks();
      expect(reads, 1);
      expect(time.periodicTimerCount, 0);
      unawaited(subscription.cancel());
      time.flushMicrotasks();
      expect(events.hasListener, isFalse);
    });
  });
  test('迟到查询不能覆盖新事件或重新订阅后的状态', () {
    fakeAsync((time) {
      final events = StreamController<Set<String>>.broadcast();
      final gate = Completer<Set<String>>();
      var calls = 0, hints = 0;
      final monitor = LocalNetworkMonitor(
        readState: () => ++calls == 1 ? gate.future : Future.value({'mobile'}),
        events: events.stream,
      );
      final first = monitor.changes.listen((_) => hints++);
      events.add({'wifi'});
      time.flushMicrotasks();
      unawaited(first.cancel());
      time.flushMicrotasks();
      final second = monitor.changes.listen((_) => hints++);
      time.flushMicrotasks();
      expect(hints, 1);
      gate.complete({'ethernet'});
      time.flushMicrotasks();
      events.add({'mobile'});
      time.flushMicrotasks();
      expect(hints, 1);
      unawaited(second.cancel());
      time.flushMicrotasks();
    });
  });
}
