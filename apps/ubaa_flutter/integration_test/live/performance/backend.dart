import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'measurement.dart';

/// 学校只读探针，使用生产 Bridge；显式阻止全部业务提交。
class MeasuredBackend extends BridgeBackend {
  MeasuredBackend._(super.client, String config, this.measurement)
    : super(configDirectory: config);
  static Future<MeasuredBackend> open(
    String config,
    StartupMeasurement measurement,
  ) async => MeasuredBackend._(
    await BridgeClient.open(configDir: config),
    config,
    measurement,
  );
  final StartupMeasurement measurement;
  final _hold = Completer<void>();

  @override
  Future<void> openOfflineAccount(LocalAccount account, List<int> key) =>
      measurement.observe(
        'cache.open',
        () => super.openOfflineAccount(account, key),
        phase: 'cache',
      );

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) =>
      measurement.observe(
        'cache.home',
        () => super.readCachedHome(policy),
        phase: 'cache',
        annotate: (value) => {'cache_entries': value.length},
      );

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    measurement.mark('recovery_rpc_started_us');
    if (measurement.scenario == 'recoveryHeld') await _hold.future;
    if (measurement.scenario == 'recoveryFailed') {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    return measurement.observe(
      'recovery.${feature.name}',
      () => super.recoverRequiredSession(feature),
      phase: 'authentication',
      annotate: (value) => {'route': value.route.name},
    );
  }

  @override
  Future<BackendRouteSettings> routeSettings() => measurement.observe(
    'routeSettings',
    super.routeSettings,
    phase: 'authentication',
  );

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    final result = await measurement.observe(
      'query.${feature.name}.${query.view.name}',
      () => super.loadFeatureQuery(feature, query),
      phase: 'upstream',
      annotate: (value) => {
        'origin': value.evidence?.origin.name,
        'complete': value.evidence?.complete,
        'error': value.error?.code.name,
        'route': value.resolvedRoute?.name,
      },
    );
    measurement.recordHomeQuery(feature, query, result);
    return result;
  }

  @override
  Future<ProfileRefresh> refreshProfile({required LocalAccount account}) =>
      measurement.observe(
        'profile.refresh',
        () => super.refreshProfile(account: account),
        phase: 'upstream',
      );

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    measurement.finishedReads.remove(feature);
    try {
      final result = await measurement.observe(
        'read.${feature.name}',
        () => super.loadFeature(feature),
        phase: 'upstream',
        annotate: (value) => {
          'origin': value.evidence?.origin.name,
          'complete': value.evidence?.complete,
          'error': value.error?.code.name,
          'route': value.resolvedRoute?.name,
        },
      );
      if (result.error != null) {
        measurement.homeSourceErrors[feature.name] = result.error!.code.name;
      }
      return result;
    } finally {
      measurement.finishedReads.add(feature);
    }
  }

  @override
  Future<FeatureReadTask?> beginAccountFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
    LocalAccount account,
  ) async {
    measurement.finishedReads.remove(feature);
    try {
      final task = await measurement.observe(
        'begin.${feature.name}',
        () => super.beginAccountFeatureRead(feature, query, account),
        phase: 'upstream',
      );
      return task == null ? null : _MeasuredTask(task, measurement, feature);
    } on Object {
      measurement.finishedReads.add(feature);
      rethrow;
    }
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    measurement.writes++;
    throw StateError('只读测量禁止任何学校业务提交');
  }

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) => commitWrite(intentId);
}

class _MeasuredTask implements FeatureReadTask {
  _MeasuredTask(this.task, this.measurement, this.feature);
  final FeatureReadTask task;
  final StartupMeasurement measurement;
  final FeatureId feature;
  @override
  Future<FeatureReadBatch> next() async {
    try {
      final result = await measurement.observe(
        'batch.${feature.name}',
        task.next,
      );
      if (result.finished) measurement.finishedReads.add(feature);
      if (result.result.error != null) {
        measurement.homeSourceErrors[feature.name] =
            result.result.error!.code.name;
      }
      return result;
    } on Object {
      measurement.finishedReads.add(feature);
      rethrow;
    }
  }

  @override
  void cancel() => task.cancel();
}
