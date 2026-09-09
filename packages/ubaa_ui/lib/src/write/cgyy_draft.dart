part of '../widgets.dart';

/// 仅当前读取帧内存；不写入账号存储、日志或学校接口。
class _CgyyFormDraft extends ChangeNotifier {
  String phone = '',
      theme = '',
      manualPurpose = '',
      people = '1',
      content = '',
      joiners = '';
  int? purpose;
  bool philosophy = false, offSchool = false, manual = false;
  int generation = 0;

  void clear() {
    phone = theme = manualPurpose = content = joiners = '';
    people = '1';
    purpose = null;
    philosophy = offSchool = manual = false;
    generation++;
    notifyListeners();
  }
}

class _CgyyFormContext {
  const _CgyyFormContext({
    required this.draft,
    this.loadPurposes,
    this.route,
    this.onRouteOptions,
  });
  final _CgyyFormDraft draft;
  final Future<FeatureResult> Function(bool forceRefresh)? loadPurposes;
  final ConnectionMode? route;
  final Future<void> Function(Map<String, ConnectionMode>)? onRouteOptions;
}
