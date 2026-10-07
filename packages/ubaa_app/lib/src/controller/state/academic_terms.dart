import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../read_scheduler.dart';
import 'read_scope.dart';

/// 成绩只借用当前学期结果，不能修改学期缓存或推断它的失效规则。
abstract interface class CurrentTermsReader {
  String? currentTermCode(ReadScope scope);
}

/// 学期结果、在途合并、优先级和失效代次由同一个所有者管理。
final class AcademicTermsOwner implements CurrentTermsReader {
  ReadScope? _scope;
  FeatureResult? _result;
  Future<FeatureResult>? _pending;
  ReadDemand? _demand;
  int _serial = 0;

  @override
  String? currentTermCode(ReadScope scope) {
    if (!scope.isCurrent || _scope?.hasSameOwner(scope) != true) return null;
    final selected = _result?.details
        .map((detail) => detail.presentation)
        .whereType<TermPresentation>()
        .where((term) => term.selected)
        .toList();
    return selected?.length == 1 ? selected!.single.code : null;
  }

  Future<FeatureResult> load({
    required ReadScope scope,
    required bool forceRefresh,
    required ReadPriority priority,
    required Future<FeatureResult> Function(
      bool Function() current,
      ReadDemand demand,
    )
    fetch,
    required FeatureResult Function() conflict,
    required void Function() pump,
  }) {
    if (!scope.isCurrent) return Future.value(conflict());
    if (_scope?.hasSameOwner(scope) != true) {
      invalidate();
      _scope = scope;
    }
    if (_pending case final pending?) {
      if (_demand?.promote(priority) == true) pump();
      return pending;
    }
    if (!forceRefresh) {
      if (_result case final result?) return Future.value(result);
    }
    _result = null;
    final serial = ++_serial;
    final demand = _demand = ReadDemand(priority);
    final completion = Completer<FeatureResult>();
    _pending = completion.future;
    bool current() => scope.isCurrent && serial == _serial;
    unawaited(() async {
      try {
        final result = await fetch(current, demand);
        if (!current()) {
          completion.complete(conflict());
        } else {
          if (result.error == null) _result = result;
          completion.complete(result);
        }
      } on Object catch (error, stackTrace) {
        if (!current()) {
          completion.complete(conflict());
        } else {
          completion.completeError(error, stackTrace);
        }
      } finally {
        if (serial == _serial) _pending = null;
      }
    }());
    return completion.future;
  }

  void invalidate() {
    _serial++;
    _scope = null;
    _result = null;
    _pending = null;
    _demand = null;
  }
}
