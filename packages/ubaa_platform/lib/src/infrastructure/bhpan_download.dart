import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:path_provider/path_provider.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class BhpanFileSaver {
  Future<BhpanDownloadDestination?> select(
    String name,
    bool Function() isCurrent,
  );
}

/// 桌面直接选择文件位置，移动端由原生通道从 Core 暂存文件流式交付。
final class SystemBhpanFileSaver implements BhpanFileSaver {
  const SystemBhpanFileSaver({
    this.operatingSystem,
    this.selectLocation,
    this.stagingDirectory,
  });
  final String? operatingSystem;
  final Future<String?> Function(String name)? selectLocation;
  final Future<Directory> Function()? stagingDirectory;
  static const channel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');
  @override
  Future<BhpanDownloadDestination?> select(
    String name,
    bool Function() current,
  ) async {
    if (!current()) return null;
    try {
      final os = operatingSystem ?? Platform.operatingSystem;
      if (os == 'android' || os == 'ios' || os == 'ohos') {
        final selection = await channel.invokeMethod<String>('select', {
          'name': name,
          'kind': 'binary',
        });
        if (selection == null) return null;
        if (!current()) {
          await channel.invokeMethod<void>('discard', {'selection': selection});
          return null;
        }
        Directory? folder;
        try {
          folder = stagingDirectory == null
              ? await (await getTemporaryDirectory()).createTemp('ubaa-bhpan-')
              : await stagingDirectory!();
          if (!current()) {
            await channel.invokeMethod<void>('discard', {
              'selection': selection,
            });
            await folder.delete(recursive: true);
            return null;
          }
          return _NativeDestination(
            '${folder.path}/download',
            folder,
            selection,
          );
        } on Object {
          await channel.invokeMethod<void>('discard', {'selection': selection});
          if (folder != null) await folder.delete(recursive: true);
          rethrow;
        }
      }
      final path = selectLocation == null
          ? (await selector.getSaveLocation(suggestedName: name))?.path
          : await selectLocation!(name);
      if (path == null || !current()) return null;
      return _DesktopDestination(path);
    } on Object {
      throw const UiError(
        code: UbaaErrorCode.unsupported,
        title: '保存位置不可用',
        message: '无法选择文件保存位置，请检查系统文件权限',
      );
    }
  }
}

final class _DesktopDestination implements BhpanDownloadDestination {
  _DesktopDestination(this.path);
  @override
  final String path;
  // 系统保存面板负责同名确认。
  @override
  bool get overwrite => true;
  @override
  Future<void> deliver(bool Function() current) async {}
  @override
  Future<void> discard() async {}
}

final class _NativeDestination implements BhpanDownloadDestination {
  _NativeDestination(this.path, this.folder, this.selection);
  @override
  final String path;
  final Directory folder;
  final String selection;
  bool consumed = false;
  @override
  bool get overwrite => false;
  @override
  Future<void> deliver(bool Function() current) async {
    if (!current())
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '会话已变化',
        message: '账号或路线已变化，文件未交付',
      );
    consumed = true;
    try {
      await SystemBhpanFileSaver.channel.invokeMethod<void>('writeFile', {
        'selection': selection,
        'path': path,
      });
    } on Object {
      throw const UiError(
        code: UbaaErrorCode.invalidInput,
        title: '文件未保存',
        message: '文件未完成保存，请检查所选位置与权限',
      );
    }
  }

  @override
  Future<void> discard() async {
    try {
      if (!consumed) {
        consumed = true;
        await SystemBhpanFileSaver.channel.invokeMethod<void>('discard', {
          'selection': selection,
        });
      }
    } finally {
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  }
}
