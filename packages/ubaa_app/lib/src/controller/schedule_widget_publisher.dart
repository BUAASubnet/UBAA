import 'dart:async';
import 'dart:convert';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 同一宿主的组件发布协调器，账号变更先撤销旧原生发布代次。
final class ScheduleWidgetPublisher {
  ScheduleWidgetPublisher(this.gateway);
  final ScheduleWidgetGateway gateway;
  int _generation = 0;
  Future<void> _beginTail = Future.value();
  Future<void> _publishTail = Future.value();
  Future<String?>? _revocation;
  int _ownerGeneration = 0;
  String? _owner, _published;
  String? _confirmedOwner;
  bool _nativeOwnerConfirmed = false;
  bool _initialized = false, _disposed = false;
  Timer? _timer;
  Completer<void>? _waiting;

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _waiting?.complete();
    _waiting = null;
  }

  Future<void> update(
    String? owner,
    Future<ScheduleWidgetSnapshot> Function(bool Function()) read, {
    bool immediate = false,
  }) {
    if (_disposed) return Future.value();
    _cancelTimer();
    final generation = ++_generation;
    final changed = !_initialized || owner != _owner;
    final needsRevocation =
        changed || !_nativeOwnerConfirmed || owner != _confirmedOwner;
    _initialized = true;
    _owner = owner;
    if (changed) {
      _published = null;
      _publishTail = Future.value();
      _revocation = null;
      _ownerGeneration++;
    }
    final ownerGeneration = _ownerGeneration;
    bool current() => !_disposed && generation == _generation;
    Future<String?> begin({required bool revoke}) {
      final task = _beginTail.then<String?>((_) async {
        if (!revoke && !current()) return null;
        final scope = await gateway.begin(owner);
        _confirmedOwner = owner;
        _nativeOwnerConfirmed = true;
        return scope;
      });
      _beginTail = task.then<void>((_) {}, onError: (Object _) {});
      return task;
    }

    Future<void> run() async {
      if (owner == null) {
        final revocation = _revocation ??= begin(revoke: true);
        try {
          await revocation;
        } on Object {
          if (identical(revocation, _revocation)) _revocation = null;
          rethrow;
        }
        return;
      }
      final scope = needsRevocation ? await begin(revoke: true) : null;
      if (!current()) return;
      final value = await read(current);
      if (!current() || value.owner != owner) return;
      final encoded = jsonEncode(value.toJson());
      final delivery = _publishTail.then((_) async {
        if (!current() || encoded == _published) return;
        final validScope = scope ?? await begin(revoke: false);
        if (!current() || validScope == null) return;
        await gateway.publish(validScope, value);
        if (!_disposed && ownerGeneration == _ownerGeneration)
          _published = encoded;
      });
      _publishTail = delivery.then<void>((_) {}, onError: (Object _) {});
      await delivery;
    }

    if (needsRevocation || immediate || owner == null) return run();
    final done = _waiting = Completer<void>();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      _waiting = null;
      _timer = null;
      done.complete(run());
    });
    return done.future;
  }

  void dispose() {
    _disposed = true;
    _cancelTimer();
    _generation++;
  }
}
