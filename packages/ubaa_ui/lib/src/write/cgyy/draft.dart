import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 仅当前读取帧内存；不写入账号存储、日志或学校接口。
class CgyyFormDraft extends ChangeNotifier {
  String phone = '', theme = '', people = '', content = '', joiners = '';
  int? purpose;
  bool philosophy = false, offSchool = false;
  int generation = 0;

  void clear() {
    phone = theme = content = joiners = '';
    people = '';
    purpose = null;
    philosophy = offSchool = false;
    generation++;
    notifyListeners();
  }
}

class CgyyFormContext {
  const CgyyFormContext({
    required this.draft,
    this.loadPurposes,
    this.loadDefaults,
    this.saveDefaults,
    this.route,
  });
  final CgyyFormDraft draft;
  final Future<FeatureResult> Function(bool forceRefresh)? loadPurposes;

  /// 上一次填写内容：未改动的输入框以灰字显示并按原值提交。
  final Future<CgyyReservationDefaults?> Function()? loadDefaults;
  final Future<void> Function(CgyyReservationDefaults)? saveDefaults;
  final ConnectionMode? route;
}
