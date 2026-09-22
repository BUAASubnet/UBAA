import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 只观察本机接口变化，不探测学校服务，也不判断认证状态。
/// 接口地址只在内存比较，不进入诊断、日志或持久存储。
final class LocalNetworkMonitor {
  LocalNetworkMonitor({Future<Set<String>> Function()? readInterfaces})
    : _readInterfaces = readInterfaces ?? _interfaces {
    _controller = StreamController<void>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }
  final Future<Set<String>> Function() _readInterfaces;
  late final StreamController<void> _controller;
  Timer? _timer;
  Set<String>? _previous;
  int _epoch = 0;
  bool _reading = false;
  Stream<void> get changes => _controller.stream;

  void _start() {
    final epoch = ++_epoch;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _read(epoch));
    unawaited(_read(epoch));
  }

  void _stop() {
    _epoch++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _read(int epoch) async {
    if (_reading || epoch != _epoch) return;
    _reading = true;
    try {
      final current = Set<String>.of(await _readInterfaces());
      if (epoch != _epoch || !_controller.hasListener) return;
      final previous = _previous;
      _previous = current;
      if (previous != null &&
          current.isNotEmpty &&
          !setEquals(previous, current)) {
        _controller.add(null);
      }
    } on Object {
      // 不支持枚举或临时失败时保持原状态；恢复退避和手动重试仍可使用。
    } finally {
      _reading = false;
    }
  }

  static Future<Set<String>> _interfaces() async => {
    for (final interface in await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    ))
      for (final address in interface.addresses)
        '${interface.name}:${address.type.name}:${address.address}',
  };
}
