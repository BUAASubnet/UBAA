import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 只发布系统连接类型变化提示，不代表校园服务可达或已认证。
final class LocalNetworkMonitor {
  LocalNetworkMonitor({
    Future<Set<String>> Function()? readState,
    Stream<Set<String>>? events,
  }) : _readState =
           readState ??
           (() async => _types(await Connectivity().checkConnectivity())),
       _events = events ?? Connectivity().onConnectivityChanged.map(_types) {
    _controller = StreamController<void>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }
  final Future<Set<String>> Function() _readState;
  final Stream<Set<String>> _events;
  late final StreamController<void> _controller;
  StreamSubscription<Set<String>>? _subscription;
  Set<String>? _previous;
  int _epoch = 0;
  int _revision = 0;
  Stream<void> get changes => _controller.stream;
  static Set<String> _types(List<ConnectivityResult> values) => {
    for (final value in values)
      if (value != ConnectivityResult.none) value.name,
  };
  void _start() {
    final epoch = ++_epoch;
    final revision = _revision;
    _subscription = _events.listen((state) {
      _revision++;
      _accept(state, epoch);
    }, onError: (Object _) {});
    unawaited(_read(epoch, revision));
  }

  Future<void> _read(int epoch, int revision) async {
    try {
      final state = await _readState();
      if (revision == _revision) _accept(state, epoch);
    } on Object {
      /* 临时失败交给既有退避及手动重试。 */
    }
  }

  void _accept(Set<String> state, int epoch) {
    if (epoch != _epoch || !_controller.hasListener) return;
    final previous = _previous;
    _previous = Set.of(state);
    if (previous != null && state.isNotEmpty && !setEquals(previous, state))
      _controller.add(null);
  }

  void _stop() {
    _epoch++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }
}
