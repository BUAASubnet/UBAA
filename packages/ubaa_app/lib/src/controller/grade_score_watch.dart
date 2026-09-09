import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'app_controller.dart';
import 'error_mapper.dart';

/// 首页按需检查；不后台轮询，不把通知或本地基线作为业务写资格。
final class GradeScoreWatch extends ChangeNotifier {
  GradeScoreWatch({required this.controller, required this.store}) {
    controller.addListener(_syncScope);
    _syncScope();
  }
  final AppController controller;
  final GradeScoreStore store;
  GradeScoreNotice? _notice;
  UiError? _error;
  ConnectionMode? _checkedRoute;
  String? _account;
  RoutePolicy? _policy;
  int _epoch = -1, _generation = 0;
  int? _checkedEpoch;
  Future<void>? _pending;
  bool _disposed = false, _checking = false;
  GradeScoreNotice? get notice => _notice;
  UiError? get error => _error;
  ConnectionMode? get checkedRoute => _checkedRoute;
  bool get isChecking => _checking;

  String? get _currentAccount {
    if (controller.phase != AppPhase.home) return null;
    final user = controller.user;
    final key = user?.schoolId?.trim().isNotEmpty == true
        ? user!.schoolId!
        : user?.username;
    return key?.trim().isNotEmpty == true ? key : null;
  }

  void _syncScope() {
    if (_disposed) return;
    final account = _currentAccount, policy = controller.loginForm.routePolicy;
    final changed = account != _account || policy != _policy;
    if (!changed && _epoch == controller.readCacheEpoch) return;
    _generation++;
    _account = account;
    _policy = policy;
    _epoch = controller.readCacheEpoch;
    _checkedEpoch = null;
    _pending = null;
    _checking = false;
    _error = null;
    _checkedRoute = null;
    if (changed) _notice = null;
    notifyListeners();
  }

  Future<void> check({bool forceRefresh = false}) {
    _syncScope();
    final account = _account;
    if (_disposed || account == null) return Future.value();
    if (_pending case final pending?) return pending;
    if (!forceRefresh && _checkedEpoch == _epoch) return Future.value();
    final completer = Completer<void>();
    _pending = completer.future;
    _checkedEpoch = _epoch;
    _checking = true;
    _error = null;
    _checkedRoute = null;
    final generation = _generation, epoch = _epoch;
    notifyListeners();
    unawaited(
      _perform(
        account,
        generation,
        epoch,
        forceRefresh,
      ).whenComplete(completer.complete),
    );
    return completer.future;
  }

  bool _current(String account, int generation, int epoch) =>
      !_disposed &&
      _generation == generation &&
      _epoch == epoch &&
      controller.readCacheEpoch == epoch &&
      _currentAccount == account;

  Future<void> _perform(
    String account,
    int generation,
    int epoch,
    bool force,
  ) async {
    try {
      final read = await controller.loadCurrentGrades(forceRefresh: force);
      if (!_current(account, generation, epoch) || read == null) return;
      _checkedRoute = read.resolvedRoute ?? read.result.error?.resolvedRoute;
      if (read.result.error case final error?) throw error;
      if (read.overview == null)
        throw UbaaErrorMapper.fromCode(UbaaErrorCode.parseError);
      final route = read.resolvedRoute;
      if (route == null)
        throw UbaaErrorMapper.fromCode(UbaaErrorCode.upstreamChanged);
      if (_notice != null &&
          (_notice!.route != route || _notice!.termCode != read.code)) {
        _notice = null;
      }
      final latest = GradeScoreBaseline.fromRead(read);
      // 首次空集合或暂时缺少身份时不覆盖已知基线。
      if (latest.scores.isEmpty) return;
      final previous = await store.read(account, route);
      if (!_current(account, generation, epoch)) return;
      final nextNotice = latest.compareWith(previous, route);
      await store.write(account, route, latest);
      if (!_current(account, generation, epoch)) return;
      // 没有新变化时，原通知保持到用户查看/忽略。
      if (nextNotice != null) _notice = nextNotice;
    } on Object catch (error) {
      if (_current(account, generation, epoch))
        _error = UbaaErrorMapper.fromObject(error);
    } finally {
      if (_current(account, generation, epoch)) {
        _pending = null;
        _checking = false;
        notifyListeners();
      }
    }
  }

  void consumeNotice() {
    if (_disposed || _notice == null) return;
    _notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    controller.removeListener(_syncScope);
    super.dispose();
  }
}
