import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/offline.dart';
import '../state/state.dart' show ControllerState;

mixin ControllerOfflineQuery on ControllerState {
  @internal
  Future<FeatureSnapshot?> internalPeekCachedQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    final backend = internalBackend;
    final account = internalLocalAccount;
    final policy = internalLoginForm.routePolicy;
    if (backend is! OfflineQueryBackend || account == null) return null;
    try {
      // 本机读取通常在几十毫秒内完成；超时则按无缓存处理，不拖慢在线读取。
      final waited = Completer<OfflineQueryRead?>();
      final limit = Timer(const Duration(milliseconds: 300), () {
        if (!waited.isCompleted) waited.complete(null);
      });
      unawaited(
        internalOfflineOpenFuture
            .then(
              (_) => (backend as OfflineQueryBackend).readCachedQuery(
                feature,
                query,
                policy,
              ),
            )
            .then<void>(
              (value) {
                if (!waited.isCompleted) waited.complete(value);
              },
              onError: (Object _) {
                if (!waited.isCompleted) waited.complete(null);
              },
            ),
      );
      final read = await waited.future;
      limit.cancel();
      final projection = read?.projection;
      if (projection == null ||
          !identical(internalBackend, backend) ||
          internalLocalAccount?.id != account.id ||
          internalLoginForm.routePolicy != policy ||
          projection.accountId != account.id ||
          projection.feature != feature ||
          !projection.readContext.hasSameQuery(query))
        return null;
      return projection.toSnapshot();
    } on Object {
      // 本机读取失败按无缓存处理；错误仍由随后的恢复流程记录。
      return null;
    }
  }

  /// 默认读取（无显式查询）开始时并行读取本机缓存；页面尚无内容时先显示缓存，
  /// 在线结果到达后照常覆盖。不阻塞在线读取。
  @internal
  Future<void> internalRestoreCachedDefault(
    FeatureId feature,
    int generation,
    int lifecycle,
    int? ygdkGeneration,
  ) async {
    final seed = await internalPeekCachedQuery(feature, const FeatureQuery());
    if (seed == null ||
        !internalIsFeatureLoadCurrent(
          feature,
          generation,
          lifecycle,
          ygdkGeneration,
        ))
      return;
    final previous = internalSnapshots[feature]!;
    if (previous.status != FeatureLoadStatus.loading ||
        previous.readContext?.query != null ||
        previous.details.isNotEmpty ||
        previous.overview != null ||
        previous.evidence != null)
      return;
    internalSnapshots[feature] = seed.copyWith(
      status: FeatureLoadStatus.loading,
      readContext: previous.readContext,
    );
    internalNotify();
  }

  @internal
  Future<void> internalRestoreCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    int generation,
    int lifecycle,
    int? ygdkGeneration,
  ) async {
    final backend = internalBackend;
    final account = internalLocalAccount;
    final policy = internalLoginForm.routePolicy;
    if (backend is! OfflineQueryBackend || account == null) return;
    bool current() =>
        identical(internalBackend, backend) &&
        internalLocalAccount?.id == account.id &&
        internalLoginForm.routePolicy == policy &&
        internalIsFeatureLoadCurrent(
          feature,
          generation,
          lifecycle,
          ygdkGeneration,
        );
    try {
      await internalOfflineOpenFuture;
      if (!current()) return;
      final read = await (backend as OfflineQueryBackend).readCachedQuery(
        feature,
        query,
        policy,
      );
      if (!current()) return;
      final projection = read.projection;
      final previous = internalSnapshots[feature]!;
      if (projection != null &&
          projection.accountId == account.id &&
          projection.feature == feature &&
          projection.readContext.hasSameQuery(query) &&
          (previous.evidence == null ||
              previous.evidence!.origin == DataOrigin.persisted) &&
          previous.status != FeatureLoadStatus.success &&
          previous.status != FeatureLoadStatus.empty) {
        internalSnapshots[feature] = projection.toSnapshot().copyWith(
          readContext: previous.readContext,
          status: previous.status == FeatureLoadStatus.loading
              ? FeatureLoadStatus.loading
              : FeatureLoadStatus.stale,
          error: previous.error,
        );
      }
      if (read.error != null)
        internalLocalCacheError = internalRecordFailure(
          read.error!,
          DiagnosticOperation.read,
          feature: feature,
        );
      internalNotify();
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      internalLocalCacheError = internalRecordFailure(
        error,
        DiagnosticOperation.read,
        feature: feature,
        stackTrace: stackTrace,
      );
      internalNotify();
    }
  }
}
