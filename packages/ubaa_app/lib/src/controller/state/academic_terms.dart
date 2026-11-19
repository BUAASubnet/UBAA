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
  final _pending = PendingFeatureRead();
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
    if (_pending.current case final pending?) {
      if (_demand?.promote(priority) == true) pump();
      return pending;
    }
    if (!forceRefresh) {
      if (_result case final result?) return Future.value(result);
    }
    _result = null;
    final serial = ++_serial;
    final demand = _demand = ReadDemand(priority);
    bool current() => scope.isCurrent && serial == _serial;
    return _pending.joinOrStart(() async {
      try {
        final result = await fetch(current, demand);
        if (!current()) return conflict();
        if (result.error == null) _result = result;
        return result;
      } on Object {
        if (!current()) return conflict();
        rethrow;
      }
    });
  }

  void invalidate() {
    _serial++;
    _scope = null;
    _result = null;
    _pending.clear();
    _demand = null;
  }
}
