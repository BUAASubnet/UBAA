import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// 发布系统网络变化和联网状态提示，不代表校园服务可达或已认证。
final class LocalNetworkMonitor {
  LocalNetworkMonitor({
    Future<Set<String>> Function()? readState,
    Stream<Set<String>>? events,
  }) : _readState =
           readState ??
           (() async => _types(await Connectivity().checkConnectivity())),
       _events =
           events ??
           ConnectivityPlatform.instance.onConnectivityChanged.map(_types) {
    _controller = StreamController<bool>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }
  final Future<Set<String>> Function() _readState;
  final Stream<Set<String>> _events;
  late final StreamController<bool> _controller;
  StreamSubscription<Set<String>>? _subscription;
  Set<String>? _previous;
  int _epoch = 0;
  int _revision = 0;
  Stream<bool> get changes => _controller.stream;
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
      if (revision == _revision) _accept(state, epoch, event: false);
    } on Object {
      /* 临时失败交给既有退避及手动重试。 */
    }
  }

  void _accept(Set<String> state, int epoch, {bool event = true}) {
    if (epoch != _epoch || !_controller.hasListener) return;
    final previous = _previous;
    _previous = Set.of(state);
    if ((previous == null && state.isEmpty) ||
        (previous != null && (event || !setEquals(previous, state))))
      _controller.add(state.isNotEmpty);
  }

  void _stop() {
    _epoch++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }
}
