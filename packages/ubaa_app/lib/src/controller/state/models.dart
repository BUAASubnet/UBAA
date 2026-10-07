import 'dart:async';
import 'read_scope.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/progressive.dart';
import 'package:ubaa_app/src/contracts/schedule_import.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';

class GuardedLockDisplaySession implements CgyyLockDisplaySession {
  GuardedLockDisplaySession(this.inner, this.isCurrent);
  final CgyyLockDisplaySession inner;
  final bool Function() isCurrent;
  bool _closed = false;
  CgyyLockDisplay? _last;
  @override
  Stream<void> get cancelled => inner.cancelled;
  void validate() {
    if (!isCurrent()) cancel();
  }

  @override
  Future<CgyyLockDisplay> read() async {
    validate();
    if (_closed)
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    final value = await inner.read();
    validate();
    if (_closed) {
      value.release();
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    _last?.release();
    return _last = value;
  }

  @override
  void cancel() {
    if (_closed) return;
    _closed = true;
    _last?.release();
    _last = null;
    inner.cancel();
  }
}

const controllerHomeDefaultFeatures = <FeatureId>[
  FeatureId.schedule,
  FeatureId.signin,
  FeatureId.spoc,
  FeatureId.judge,
  FeatureId.ygdk,
];

final class ProgressiveScope {
  ProgressiveScope(this.feature, this.query, this.current);
  final FeatureId feature;
  final FeatureQuery? query;
  final bool Function() current;
  FeatureReadTask? task;
  ConnectionMode? route;
  bool restartRequested = false;
  final completion = Completer<void>();
  bool cancelled = false;
  bool get valid => !cancelled && current();
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    task?.cancel();
  }
}

final class FeatureReadStart {
  const FeatureReadStart({this.task, this.result});
  final FeatureReadTask? task;
  final FeatureResult? result;
}

final class ScheduleImportScope {
  ScheduleImportScope(this.ownerCurrent);
  final bool Function() ownerCurrent;
  final completion = Completer<void>();
  ScheduleImportTask? task;
  bool cancelled = false;
  bool get valid => !cancelled && ownerCurrent();
  void cancel() {
    cancelled = true;
    task?.cancel();
  }
}

final class ReadPlanRestart implements Exception {
  const ReadPlanRestart();
}

final class AcademicWeeksCache {
  AcademicWeeksCache(this.backend, this.lifecycle, this.epoch);
  final UbaaBackend backend;
  final int lifecycle, epoch;
  final entries = <String, AcademicWeekEntry>{};
}

final class AcademicWeekEntry {
  final completer = Completer<FeatureResult>();
  bool pending = true;
}

final class CgyyPurposeCache {
  CgyyPurposeCache(this.backend, this.lifecycle, this.epoch);
  final UbaaBackend backend;
  final int lifecycle, epoch;
  final completer = Completer<FeatureResult>();
  bool pending = true;
}

final class HomeSupplementCache {
  HomeSupplementCache(this.backend, this.lifecycle, this.epoch);
  final UbaaBackend backend;
  final int lifecycle, epoch;
  final entries = <HomeSupplement, HomeSupplementEntry>{};
}

final class HomeSupplementEntry {
  final completer = Completer<FeatureResult>();
  bool pending = true;
}

final class GradesReadCache {
  GradesReadCache(this.scope);
  final ReadScope scope;
  final entries = <String, GradeReadEntry>{};
  Future<GradesAggregate>? aggregatePending;
  UiError? authenticationError;
}

final class GradeReadEntry {
  GradeReadEntry([ReadPriority priority = ReadPriority.interactive])
    : demand = ReadDemand(priority);
  final ReadDemand demand;
  final completer = Completer<FeatureResult>();
  bool pending = true;
  bool freshForAggregate = false;
  FeatureResult? result;
}

final class WriteRefreshRequest {
  WriteRefreshRequest(this.current);
  final bool Function() current;
}

final class WriteReadbackRead {
  WriteReadbackRead(this.epoch, this.revision);
  final int epoch, revision;
  final completion = Completer<void>();
}

enum YgdkReadbackSlot { overview, records }

final class ProfileRequest {
  ProfileRequest(this.backend, this.accountId, this.epoch, this.policy);
  final UbaaBackend backend;
  final String accountId;
  final int epoch;
  final RoutePolicy policy;
  final completion = Completer<void>();
}

final class RecoveryRequest {
  RecoveryRequest(this.feature, this.epoch, this.refreshHomeAfter)
    : interactive = !refreshHomeAfter;
  final FeatureId feature;
  int epoch;
  bool refreshHomeAfter;
  bool interactive;
  bool transientFailure = false;
  ConnectionMode? replacedRoute;
  bool replacedAllRoutes = false;
  final queriesAfterRebuild = <FeatureId, FeatureQuery>{};
  final completion = Completer<void>();
}

const controllerRecoveryRetryDelays = [
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(minutes: 5),
];

final class RecoveryRetry {
  RecoveryRetry(this.epoch, this.attempt, this.query);
  final int epoch;
  final int attempt;
  final FeatureQuery? query;
  Timer? timer;
  bool due = false;
  bool queued = false;
}

/// 默认首页与显式查询各自绑定请求修订，不重试写后回读或学校提交。
final class BusinessRetry {
  BusinessRetry(this.epoch, this.revision, this.query, this.attempt);
  final int epoch;
  int revision;
  final FeatureQuery? query;
  final int attempt;
  Timer? timer;
  bool due = false;
  bool running = false;
}
