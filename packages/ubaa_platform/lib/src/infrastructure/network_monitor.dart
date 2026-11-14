import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 发布系统网络变化和联网状态提示，不代表校园服务可达或已认证。
final class LocalNetworkMonitor {
  LocalNetworkMonitor({
    Future<Set<String>> Function()? readState,
    Stream<Set<String>>? events,
  }) : _readState =
           readState ??
           (_android
               ? () async =>
                     _identity(await _methods.invokeMethod<String>('current'))
               : () async => _types(await Connectivity().checkConnectivity())),
       _events =
           events ??
           (_android
               ? const EventChannel('cn.edu.ubaa/default_network/events')
                     .receiveBroadcastStream()
                     .map((value) => _identity(value as String?))
               : ConnectivityPlatform.instance.onConnectivityChanged.map(
                   _types,
                 )) {
    _controller = StreamController<bool>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static const _methods = MethodChannel('cn.edu.ubaa/default_network');
  static Set<String> _identity(String? value) => value == null ? {} : {value};
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
        (previous != null &&
            ((event && !_android) || !setEquals(previous, state))))
      _controller.add(state.isNotEmpty);
  }

  void _stop() {
    _epoch++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }
}
