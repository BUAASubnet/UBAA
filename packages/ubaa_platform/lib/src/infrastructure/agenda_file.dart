import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart' as selector;

/// 系统文件对话框取消与保存完成分别返回，不暴露选择的本机路径。
enum AgendaFileResult { saved, cancelled, superseded, savedBeforeScopeChange }

final class AgendaFileException implements Exception {
  const AgendaFileException();
  @override
  String toString() => '日程文件未保存，请检查位置与权限后重试';
}

abstract interface class AgendaFileSaver {
  Future<AgendaFileResult> save(
    String ics,
    String name,
    bool Function() isCurrent,
  );
}

/// 桌面及移动系统保存面板。等待用户选择期间不持有业务句柄锁。
final class SystemAgendaFileSaver implements AgendaFileSaver {
  const SystemAgendaFileSaver({
    this.selectLocation,
    this.writeFile,
    this.operatingSystem,
  });
  final Future<String?> Function(String name)? selectLocation;
  final Future<void> Function(String path, Uint8List bytes)? writeFile;
  final String? operatingSystem;
  static const _channel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');
  @override
  Future<AgendaFileResult> save(
    String ics,
    String name,
    bool Function() isCurrent,
  ) async {
    try {
      if (!isCurrent()) return AgendaFileResult.superseded;
      final os = operatingSystem ?? Platform.operatingSystem;
      if (os == 'android' || os == 'ios' || os == 'ohos') {
        final selection = await _channel.invokeMethod<String>('select', {
          'name': name,
        });
        if (selection == null)
          return isCurrent()
              ? AgendaFileResult.cancelled
              : AgendaFileResult.superseded;
        if (!isCurrent()) {
          await _channel.invokeMethod<void>('discard', {
            'selection': selection,
          });
          return AgendaFileResult.superseded;
        }
        // 选择结束并确认作用域后，才把日历内容交给原生写入。提交后不能撤回文件。
        await _channel.invokeMethod<void>('write', {
          'selection': selection,
          'bytes': Uint8List.fromList(utf8.encode(ics)),
        });
        return isCurrent()
            ? AgendaFileResult.saved
            : AgendaFileResult.savedBeforeScopeChange;
      }
      final target = selectLocation == null
          ? (await selector.getSaveLocation(
              suggestedName: name,
              acceptedTypeGroups: const [
                selector.XTypeGroup(label: '日历文件', extensions: ['ics']),
              ],
            ))?.path
          : await selectLocation!(name);
      if (!isCurrent()) return AgendaFileResult.superseded;
      if (target == null) return AgendaFileResult.cancelled;
      final bytes = Uint8List.fromList(utf8.encode(ics));
      if (writeFile != null) {
        await writeFile!(target, bytes);
      } else {
        await selector.XFile.fromData(
          bytes,
          mimeType: 'text/calendar',
          name: name,
        ).saveTo(target);
      }
      return isCurrent()
          ? AgendaFileResult.saved
          : AgendaFileResult.savedBeforeScopeChange;
    } on Object {
      throw const AgendaFileException();
    }
  }
}
