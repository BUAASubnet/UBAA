import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// “我的”页面的读取：先显示本机快照，再在后台在线刷新。
///
/// 三组数据分别更新；刷新保留旧值直至新结果到达，失败时旧值与错误同时显示。
/// 再次进入时距上次成功刷新超过 [_campusStaleAfter] 才后台刷新。
class CampusAccountLoader {
  CampusAccountLoader({
    required CampusAccountService? service,
    required this.changed,
    required DateTime Function() now,
  }) : _service = service,
       _now = now;
  CampusAccountService? _service;
  final VoidCallback changed;
  final DateTime Function() _now;
  bool _disposed = false;
  bool _online = true;
  CampusAccountOverview? _campusOverview;
  CampusAccountOverview? get overview => _campusOverview;
  Future<void>? _campusRefresh;
  DateTime? _campusRefreshedAt;
  int _campusRevision = 0;
  void _setCampusOverview(CampusAccountOverview value) {
    if (_disposed) return;
    _campusOverview = value;
    changed();
  }

  void dispose() {
    _disposed = true;
    _campusRevision++;
  }

  static const _campusStaleAfter = Duration(minutes: 5);

  /// 同账号服务重建只撤销读取任务，已展示内容保留至刷新完成。
  void bind(CampusAccountService? service, {bool keepContent = false}) {
    _service = service;
    _campusRevision++;
    if (!keepContent) _campusOverview = null;
    _campusRefresh = null;
    _campusRefreshedAt = null;
  }

  void ensure({bool online = true}) {
    _online = online;
    final service = _service;
    if (service == null || _campusRefresh != null) return;
    if (_campusOverview == null) {
      unawaited(_loadCampusAccount(service));
      return;
    }
    final refreshedAt = _campusRefreshedAt;
    if (online &&
        (refreshedAt == null ||
            _now().difference(refreshedAt) >= _campusStaleAfter)) {
      unawaited(refresh());
    }
  }

  /// 首次进入：先显示本机快照，再在线刷新。快照读取失败按无快照处理。
  Future<void> _loadCampusAccount(CampusAccountService service) {
    final revision = _campusRevision;
    _setCampusOverview(
      const CampusAccountOverview(
        identity: CampusSection.loading(),
        metrics: CampusSection.loading(),
        network: CampusSection.loading(),
      ),
    );
    late final Future<void> load;
    load =
        (() async {
          CampusAccountSnapshot snapshot;
          try {
            snapshot = await service.cached();
          } on Object {
            snapshot = const CampusAccountSnapshot();
          }
          if (_disposed ||
              revision != _campusRevision ||
              !identical(service, _service)) {
            return;
          }
          _setCampusOverview(
            CampusAccountOverview(
              identity: CampusSection.loading(snapshot.identity),
              metrics: CampusSection.loading(snapshot.metrics),
              network: CampusSection.loading(snapshot.network),
            ),
          );
          if (identical(_campusRefresh, load)) _campusRefresh = null;
          if (_online) await refresh();
        })().whenComplete(() {
          if (identical(_campusRefresh, load)) _campusRefresh = null;
        });
    _campusRefresh = load;
    return load;
  }

  Future<void> refresh() {
    final pending = _campusRefresh;
    if (pending != null) return pending;
    final service = _service;
    if (service == null) return Future<void>.value();
    final revision = _campusRevision;
    final previous = _campusOverview ?? const CampusAccountOverview();
    _setCampusOverview(
      CampusAccountOverview(
        identity: CampusSection.loading(previous.identity.data),
        metrics: CampusSection.loading(previous.metrics.data),
        network: CampusSection.loading(previous.network.data),
      ),
    );

    bool current() =>
        !_disposed &&
        revision == _campusRevision &&
        identical(service, _service);

    Future<void> load<T>(
      Future<T> Function() read,
      CampusAccountOverview Function(
        CampusAccountOverview overview,
        CampusSection<T> section,
      )
      apply,
      T? Function(CampusAccountOverview overview) old,
    ) async {
      CampusSection<T> section;
      try {
        section = CampusSection.ready(await read());
      } on UiError catch (error) {
        if (!current()) return;
        section = CampusSection.failed(error.message, old(_campusOverview!));
      } on Object {
        if (!current()) return;
        section = CampusSection.failed('读取失败，请稍后重试。', old(_campusOverview!));
      }
      if (!current()) return;
      _setCampusOverview(apply(_campusOverview!, section));
    }

    late final Future<void> refresh;
    refresh =
        Future.wait([
              load<PortalIdentity>(
                service.identity,
                (o, s) => CampusAccountOverview(
                  identity: s,
                  metrics: o.metrics,
                  network: o.network,
                ),
                (o) => o.identity.data,
              ),
              load<CampusMetrics>(
                service.metrics,
                (o, s) => CampusAccountOverview(
                  identity: o.identity,
                  metrics: s,
                  network: o.network,
                ),
                (o) => o.metrics.data,
              ),
              load<NetworkUsage>(
                service.networkUsage,
                (o, s) => CampusAccountOverview(
                  identity: o.identity,
                  metrics: o.metrics,
                  network: s,
                ),
                (o) => o.network.data,
              ),
            ])
            .then((_) {
              final o = _campusOverview;
              // 任一组失败时不记时间，下次进入会再试。
              if (current() &&
                  o != null &&
                  o.identity.error == null &&
                  o.metrics.error == null &&
                  o.network.error == null) {
                _campusRefreshedAt = _now();
              }
            })
            .whenComplete(() {
              if (identical(_campusRefresh, refresh)) _campusRefresh = null;
            });
    _campusRefresh = refresh;
    return refresh;
  }
}
