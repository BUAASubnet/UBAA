import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_host/src/network_monitor.dart';

void main() {
  test('本机接口首次观察与离线不唤醒，连接变化才提示，取消后无轮询', () {
    fakeAsync((time) {
      var interfaces = <String>{};
      var calls = 0;
      var hints = 0;
      final monitor = LocalNetworkMonitor(
        readInterfaces: () async {
          calls++;
          return interfaces;
        },
      );
      final subscription = monitor.changes.listen((_) => hints++);
      time.flushMicrotasks();
      expect(hints, 0);
      interfaces = {'synthetic-a'};
      time.elapse(const Duration(seconds: 5));
      time.flushMicrotasks();
      time.flushMicrotasks();
      expect(hints, 1);
      time.elapse(const Duration(seconds: 5));
      time.flushMicrotasks();
      expect(hints, 1);
      interfaces = {};
      time.elapse(const Duration(seconds: 5));
      time.flushMicrotasks();
      expect(hints, 1);
      interfaces = {'synthetic-b'};
      time.elapse(const Duration(seconds: 5));
      time.flushMicrotasks();
      time.flushMicrotasks();
      expect(hints, 2);
      unawaited(subscription.cancel());
      time.flushMicrotasks();
      final stopped = calls;
      time.elapse(const Duration(minutes: 1));
      time.flushMicrotasks();
      expect(calls, stopped);
      expect(time.periodicTimerCount, 0);
    });
  });
  test('枚举失败不宣称联网，取消订阅后的迟到枚举不能改变新订阅基线', () {
    fakeAsync((time) {
      var calls = 0;
      final gate = Completer<Set<String>>();
      final monitor = LocalNetworkMonitor(
        readInterfaces: () async {
          calls++;
          if (calls == 1) throw StateError('合成枚举不可用');
          if (calls == 2) return gate.future;
          return {'synthetic-new'};
        },
      );
      var hints = 0;
      final first = monitor.changes.listen((_) => hints++);
      time.flushMicrotasks();
      expect(hints, 0);
      time.elapse(const Duration(seconds: 5));
      time.flushMicrotasks();
      unawaited(first.cancel());
      time.flushMicrotasks();
      final second = monitor.changes.listen((_) => hints++);
      gate.complete({'synthetic-old'});
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 5));
      time.flushMicrotasks();
      time.flushMicrotasks();
      expect(hints, 0);
      unawaited(second.cancel());
      time.flushMicrotasks();
      expect(time.periodicTimerCount, 0);
    });
  });
}
