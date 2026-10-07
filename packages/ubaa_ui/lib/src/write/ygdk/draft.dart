import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 草稿仅属于当前读取代次；照片由表单持有，关闭即释放。
class YgdkFormDraft extends ChangeNotifier {
  String start = '', end = '', place = '操场';
  String? itemKey;
  bool share = false;
  int generation = 0;

  void clear() {
    start = end = '';
    place = '操场';
    itemKey = null;
    share = false;
    generation++;
    notifyListeners();
  }
}

class YgdkFormContext {
  const YgdkFormContext({required this.draft, this.route, this.onRouteOptions});
  final YgdkFormDraft draft;
  final ConnectionMode? route;
  final Future<void> Function(Map<String, ConnectionMode>)? onRouteOptions;
}

String uiYgdkItemKey(YgdkSubmitAction action) =>
    '${action.classifyId}:${action.itemId}';
