import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

const measuredFeatures = [
  FeatureId.schedule,
  FeatureId.signin,
  FeatureId.spoc,
  FeatureId.judge,
  FeatureId.ygdk,
];
const measuredHomeSources = [
  'bykcChosen',
  'cgyyOrders',
  'currentWeek',
  'gradeCheck',
];

/// 独立验收入口；只输出封闭枚举、数量和时间，不保存账号或业务正文。
class StartupMeasurement with WidgetsBindingObserver {
  StartupMeasurement(this.output, this.route, this.scenario);
  final File output;
  final String route, scenario;
  final times = <String, int>{};
  final operations = <Map<String, Object?>>[];
  final activeOperations = <int, Map<String, Object?>>{};
  final lifecycle = <Map<String, Object?>>[];
  final _frames = <int, Set<String>>{};
  final outcomes = <String, Map<String, Object?>>{};
  final states = <Map<String, Object?>>[];
  final frameDiagnostics = <Map<String, Object?>>[];
  String? _previousState;
  final finishedReads = <FeatureId>{};
  final finishedHomeSources = <String>{};
  final homeSourceErrors = <String, String?>{};
  bool gradeCheckComplete = false;
  bool gradeCheckPersisted = false;
  final schedulerTraces = <Map<String, Object?>>[];
  bool _finished = false, truncated = false;
  int writes = 0, unmatchedFrames = 0;
  Timer? _timeout;
  Timer? _diagnosticTimer;
  int _operationId = 0;

  void recordHomeQuery(
    FeatureId feature,
    FeatureQuery query,
    FeatureResult result,
  ) {
    final source = switch (query.view) {
      FeatureQueryView.bykcChosenCourses => 'bykcChosen',
      FeatureQueryView.cgyyOrders => 'cgyyOrders',
      FeatureQueryView.scheduleWeeks => 'currentWeek',
      _ when feature == FeatureId.grades && query.term != null => 'gradeCheck',
      _ => null,
    };
    if (source == null) return;
    finishedHomeSources.add(source);
    if (result.error != null) {
      homeSourceErrors[source] = result.error!.code.name;
    }
  }

  void recordScheduler(ReadSchedulerTrace trace) {
    if (schedulerTraces.length >= 10000) {
      truncated = true;
      return;
    }
    schedulerTraces.add({
      'kind': trace.kind.name,
      'priority': trace.priority.name,
      'at_us': trace.atUs,
      'wait_us': trace.waitUs,
      'run_us': trace.runUs,
    });
  }

  void markGradeCheckComplete(bool persisted) {
    gradeCheckComplete = true;
    gradeCheckPersisted = persisted;
  }

  void mark(String name, [int? at]) {
    final first = !times.containsKey(name);
    times.putIfAbsent(name, () => at ?? DateTime.now().microsecondsSinceEpoch);
    if (first) stdout.writeln('startup_event=$name at_us=${times[name]}');
    if (!_finished &&
        scenario != 'online' &&
        times.containsKey('cache_visible_us') &&
        times.containsKey('recovery_rpc_started_us')) {
      unawaited(finish('cache_only'));
    }
  }

  Future<T> observe<T>(
    String operation,
    Future<T> Function() action, {
    String? phase,
    Map<String, Object?> Function(T value)? annotate,
  }) async {
    final start = DateTime.now().microsecondsSinceEpoch;
    final id = _operationId++;
    activeOperations[id] = {'operation': operation, 'start_us': start};
    stdout.writeln('startup_operation_begin=$operation at_us=$start');
    var success = false;
    Map<String, Object?>? annotation;
    try {
      final result = await action();
      success = true;
      annotation = annotate?.call(result);
      return result;
    } finally {
      final end = DateTime.now().microsecondsSinceEpoch;
      activeOperations.remove(id);
      stdout.writeln(
        'startup_operation=$operation elapsed_us=${end - start} success=$success',
      );
      if (operations.length < 10000) {
        final operationRecord = <String, Object?>{
          'operation': operation,
          'start_us': start,
          'end_us': end,
          'success': success,
        };
        if (phase != null) operationRecord['phase'] = phase;
        if (annotation != null) operationRecord.addAll(annotation);
        operations.add(operationRecord);
      } else {
        truncated = true;
      }
    }
  }

  void watchFrames() {
    WidgetsBinding.instance.addObserver(this);
    _recordLifecycle(WidgetsBinding.instance.lifecycleState?.name ?? 'unknown');
    WidgetsBinding.instance.addTimingsCallback(_rasterized);
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (_finished) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _built());
    });
    _timeout = Timer(const Duration(minutes: 10), () => finish('timeout'));
    _diagnosticTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      stdout.writeln(
        'startup_pending=${jsonEncode({'at_us': DateTime.now().microsecondsSinceEpoch, 'active_operations': activeOperations.values.toList(), 'lifecycle': lifecycle.lastOrNull, 'completed_operations': operations.length})}',
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _recordLifecycle(state.name);

  void _recordLifecycle(String state) {
    final event = {
      'at_us': DateTime.now().microsecondsSinceEpoch,
      'state': state,
    };
    if (lifecycle.length < 10000) lifecycle.add(event);
    stdout.writeln('startup_lifecycle=${jsonEncode(event)}');
  }

  void _built() {
    if (_finished) return;
    UbaaMainShell? shell;
    void visit(Element element) {
      if (element.widget case final UbaaMainShell value) shell = value;
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    visit(root);
    final current = shell;
    if (current == null) return;
    mark('home_build_end_us');
    final events = <String>{'home_frame_us'};
    final snapshots = current.homeSnapshots ?? current.snapshots;
    final state = <String, Object?>{
      for (final feature in measuredFeatures)
        feature.name: {
          'state': snapshots[feature]?.status.name,
          'origin': snapshots[feature]?.evidence?.origin.name,
          'complete': snapshots[feature]?.evidence?.complete,
          'error': snapshots[feature]?.error?.code.name,
          'count': snapshots[feature]?.details.length,
          'read_finished': finishedReads.contains(feature),
        },
      'home_sources': {
        for (final source in measuredHomeSources)
          source: {
            'finished': finishedHomeSources.contains(source),
            'error': homeSourceErrors[source],
            if (source == 'gradeCheck') 'check_complete': gradeCheckComplete,
            if (source == 'gradeCheck') 'persisted': gradeCheckPersisted,
          },
      },
    };
    final encoded = jsonEncode(state);
    if (encoded != _previousState) {
      _previousState = encoded;
      if (states.length < 10000) {
        states.add({'at_us': DateTime.now().microsecondsSinceEpoch, ...state});
        stdout.writeln('startup_state=$encoded');
      } else {
        truncated = true;
      }
    }
    final cacheVisible = [FeatureId.schedule, FeatureId.spoc].every(
      (feature) => snapshots[feature]?.evidence?.origin == DataOrigin.persisted,
    );
    if (cacheVisible) events.add('cache_visible_us');
    if (measuredFeatures.any((feature) {
      final snapshot = snapshots[feature];
      return snapshot?.evidence?.origin == DataOrigin.online ||
          snapshot?.evidence?.origin == DataOrigin.mixed;
    })) {
      events.add('first_data_visible_us');
    }
    final settled =
        measuredFeatures.every((feature) {
          final status = snapshots[feature]?.status;
          return finishedReads.contains(feature) &&
              status != null &&
              status != FeatureLoadStatus.idle &&
              status != FeatureLoadStatus.loading;
        }) &&
        measuredHomeSources.every(finishedHomeSources.contains) &&
        gradeCheckComplete;
    if (settled) {
      events.add('all_refresh_settled_us');
      final complete =
          measuredFeatures.every((feature) {
            final value = snapshots[feature]!;
            return (value.status == FeatureLoadStatus.success ||
                    value.status == FeatureLoadStatus.empty) &&
                value.evidence?.complete == true &&
                value.error == null;
          }) &&
          measuredHomeSources.every(
            (source) =>
                finishedHomeSources.contains(source) &&
                homeSourceErrors[source] == null,
          );
      if (complete) events.add('all_refresh_done_us');
      for (final feature in measuredFeatures) {
        final value = snapshots[feature]!;
        outcomes[feature.name] = {
          'state': value.status.name,
          'count': value.details.length,
          'complete': value.evidence?.complete,
          'error': value.error?.code.name,
          'route': value.resolvedRoute?.name,
        };
      }
      for (final source in measuredHomeSources) {
        outcomes[source] = {
          'finished': finishedHomeSources.contains(source),
          'error': homeSourceErrors[source],
          if (source == 'gradeCheck') 'check_complete': gradeCheckComplete,
          if (source == 'gradeCheck') 'persisted': gradeCheckPersisted,
        };
      }
    }
    final frameNumber = ui.PlatformDispatcher.instance.frameData.frameNumber;
    _frames[frameNumber] = events;
  }

  void _rasterized(List<ui.FrameTiming> frames) {
    for (final frame in frames) {
      final events = _frames.remove(frame.frameNumber);
      if (events case null) {
        unmatchedFrames++;
        if (frameDiagnostics.length < 40) {
          frameDiagnostics.add({
            'engine_frame': frame.frameNumber,
            'pending_frames': _frames.keys.take(40).toList(),
          });
        }
        continue;
      }
      final raster = frame.timestampInMicroseconds(
        ui.FramePhase.rasterFinishWallTime,
      );
      for (final event in events) {
        mark(event, raster);
      }
    }
    if (_finished) return;
    if (times.containsKey('all_refresh_settled_us')) {
      unawaited(finish('settled'));
    } else if (scenario != 'online' &&
        times.containsKey('cache_visible_us') &&
        times.containsKey('recovery_rpc_started_us')) {
      unawaited(finish('cache_only'));
    }
  }

  Future<void> finish(String status) async {
    if (_finished) return;
    _finished = true;
    _timeout?.cancel();
    _diagnosticTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final temporary = File('${output.path}.pending');
    await temporary.writeAsString(
      jsonEncode({
        'schema': 1,
        'pid': pid,
        'route': route,
        'scenario': scenario,
        'display': {
          'width_px':
              ui.PlatformDispatcher.instance.implicitView?.physicalSize.width,
          'height_px':
              ui.PlatformDispatcher.instance.implicitView?.physicalSize.height,
          'device_pixel_ratio':
              ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio,
          'text_scale_factor': ui.PlatformDispatcher.instance.textScaleFactor,
          'platform_brightness':
              ui.PlatformDispatcher.instance.platformBrightness.name,
        },
        'build': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'status': status,
        'times': times,
        'outcomes': outcomes,
        'operations': operations,
        'scheduler_traces': schedulerTraces,
        'active_operations': activeOperations.values.toList(),
        'lifecycle': lifecycle,
        'states': states,
        'frame_diagnostics': frameDiagnostics,
        'business_writes': writes,
        'trace_truncated': truncated,
        'unmatched_frames': unmatchedFrames,
      }),
      flush: true,
    );
    await temporary.rename(output.path);
  }
}
