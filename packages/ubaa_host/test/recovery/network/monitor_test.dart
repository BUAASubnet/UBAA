import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('Android 默认网络身份去重，同时识别同类型换网和断网恢复', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    fakeAsync((time) {
      final events = StreamController<Set<String>>.broadcast();
      final monitor = LocalNetworkMonitor(
        readState: () async => {'336'},
        events: events.stream,
      );
      final hints = <bool>[];
      final subscription = monitor.changes.listen(hints.add);
      time.flushMicrotasks();
      for (final state in [
        <String>{'336'},
        {'336'},
        {'337'},
        <String>{},
        <String>{},
        {'338'},
      ]) {
        events.add(state);
        time.flushMicrotasks();
      }
      expect(hints, [true, false, true]);
      unawaited(subscription.cancel());
      time.flushMicrotasks();
      final resumed = monitor.changes.listen(hints.add);
      time.flushMicrotasks();
      expect(hints, [true, false, true, true]);
      events.add({'336'});
      time.flushMicrotasks();
      expect(hints, [true, false, true, true]);
      unawaited(resumed.cancel());
      unawaited(events.close());
      time.flushMicrotasks();
    });
  });
  test('同类型网络变化与断网都通知恢复流程', () {
    fakeAsync((time) {
      final events = StreamController<Set<String>>.broadcast();
      final monitor = LocalNetworkMonitor(
        readState: () async => {'wifi'},
        events: events.stream,
      );
      var hints = 0;
      final subscription = monitor.changes.listen((_) => hints++);
      time.flushMicrotasks();
      for (final state in [
        <String>{'wifi'},
        <String>{},
        <String>{'mobile'},
      ]) {
        events.add(state);
        time.flushMicrotasks();
      }
      expect(hints, 3);
      unawaited(subscription.cancel());
      unawaited(events.close());
      time.flushMicrotasks();
    });
  });
  test('系统事件完整交付且没有周期轮询', () {
    fakeAsync((time) {
      final events = StreamController<Set<String>>.broadcast();
      var reads = 0;
      final hints = <bool>[];
      final monitor = LocalNetworkMonitor(
        readState: () async {
          reads++;
          return {};
        },
        events: events.stream,
      );
      final subscription = monitor.changes.listen(hints.add);
      time.flushMicrotasks();
      expect(hints, [false]);
      for (final state in [
        <String>{'wifi'},
        {'wifi'},
        <String>{},
        {'mobile'},
      ]) {
        events.add(state);
        time.flushMicrotasks();
      }
      expect(hints, [false, true, true, false, true]);
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
      expect(hints, 2);
      unawaited(second.cancel());
      time.flushMicrotasks();
    });
  });
}
