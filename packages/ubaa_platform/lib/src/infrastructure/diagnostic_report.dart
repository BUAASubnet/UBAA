import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/services.dart';

/// 用户主动交付的脱敏诊断报告。系统分享面板由用户选择接收方。
final class DiagnosticReportExporter {
  const DiagnosticReportExporter({this.operatingSystem});
  final String? operatingSystem;
  String get _platform => operatingSystem ?? Platform.operatingSystem;
  bool get supportsSharing =>
      const ['android', 'ios', 'ohos', 'macos'].contains(_platform);
  static const channel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');

  /// 返回保存成功的提示；打开分享面板或取消保存时不宣称文件已发送。
  Future<String?> export(String report) async {
    final name =
        'UBAA-report-${DateTime.now().toUtc().microsecondsSinceEpoch}.json';
    final bytes = Uint8List.fromList(utf8.encode(report));
    if (supportsSharing) {
      await channel.invokeMethod<void>('shareReport', {
        'name': name,
        'bytes': bytes,
      });
      return null;
    }
    final location = await selector.getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        selector.XTypeGroup(label: '错误报告', extensions: ['json']),
      ],
    );
    if (location == null) return null;
    await selector.XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: name,
    ).saveTo(location.path);
    return '报告文件已保存';
  }
}
