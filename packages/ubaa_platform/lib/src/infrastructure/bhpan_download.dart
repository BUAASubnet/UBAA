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

/// 在支持系统预览的平台上，把 Core 下载的临时文件交给系统预览器。
abstract interface class BhpanFilePreviewer {
  bool get isAvailable;
  Future<BhpanDownloadDestination?> select(
    String name,
    bool Function() isCurrent,
  );
}

/// iOS 使用 Quick Look 预览文件；其它平台保持空回调，由界面显示下载操作。
final class SystemBhpanFilePreviewer implements BhpanFilePreviewer {
  const SystemBhpanFilePreviewer({this.operatingSystem, this.stagingDirectory});

  final String? operatingSystem;
  final Future<Directory> Function()? stagingDirectory;
  static const channel = MethodChannel('cn.edu.buaa.ubaa/bhpan-preview');

  @override
  bool get isAvailable =>
      (operatingSystem ?? Platform.operatingSystem) == 'ios';

  @override
  Future<BhpanDownloadDestination?> select(
    String name,
    bool Function() isCurrent,
  ) async {
    if (!isAvailable || !isCurrent()) return null;
    Directory? folder;
    try {
      folder = stagingDirectory == null
          ? await (await getTemporaryDirectory()).createTemp(
              'ubaa-bhpan-preview-',
            )
          : await stagingDirectory!();
      if (!isCurrent()) {
        await folder.delete(recursive: true);
        return null;
      }
      final safeName = name.replaceAll(RegExp(r'[\\/\r\n]'), '_').trim();
      final path = '${folder.path}/${safeName.isEmpty ? 'preview' : safeName}';
      return _PreviewDestination(path, folder);
    } on Object {
      if (folder != null && await folder.exists()) {
        await folder.delete(recursive: true);
      }
      throw const UiError(
        code: UbaaErrorCode.unsupported,
        title: '文件预览不可用',
        message: '无法准备系统预览，请检查本机存储权限',
      );
    }
  }
}

final class _PreviewDestination implements BhpanDownloadDestination {
  _PreviewDestination(this.path, this.folder);

  @override
  final String path;
  final Directory folder;

  @override
  bool get overwrite => true;

  @override
  Future<void> deliver(bool Function() isCurrent) async {
    if (!isCurrent()) throw _previewSessionChanged;
    try {
      await SystemBhpanFilePreviewer.channel.invokeMethod<void>('preview', {
        'path': path,
      });
      if (!isCurrent()) throw _previewSessionChanged;
    } on UiError {
      rethrow;
    } on PlatformException catch (error) {
      throw UiError(
        code: error.code == 'unsupported'
            ? UbaaErrorCode.unsupported
            : UbaaErrorCode.invalidInput,
        title: '文件预览失败',
        message: '无法打开系统预览，请稍后重试',
      );
    } on Object {
      throw const UiError(
        code: UbaaErrorCode.invalidInput,
        title: '文件预览失败',
        message: '无法打开系统预览，请稍后重试',
      );
    }
  }

  @override
  Future<void> discard() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}

const _previewSessionChanged = UiError(
  code: UbaaErrorCode.operationConflict,
  title: '登录状态已变化',
  message: '账号或网络已切换，文件未保存',
);

/// 桌面直接选择文件位置，移动端通过系统授权交付 Core 暂存文件。
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
            os == 'ohos',
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
  _NativeDestination(this.path, this.folder, this.selection, this.ohos);
  @override
  final String path;
  final Directory folder;
  final String selection;
  final bool ohos;
  static const _sessionChanged = UiError(
    code: UbaaErrorCode.operationConflict,
    title: '登录状态已变化',
    message: '账号或网络已切换，文件未保存',
  );
  bool consumed = false;
  @override
  bool get overwrite => false;
  @override
  Future<void> deliver(bool Function() current) async {
    if (!current()) throw _sessionChanged;
    consumed = true;
    try {
      if (ohos) {
        await _deliverOhos(current);
      } else {
        await SystemBhpanFileSaver.channel.invokeMethod<void>('writeFile', {
          'selection': selection,
          'path': path,
        });
      }
    } on UiError {
      rethrow;
    } on PlatformException catch (error) {
      throw UiError(
        code: error.code == 'unsupported_destination'
            ? UbaaErrorCode.unsupported
            : UbaaErrorCode.invalidInput,
        title: '文件未保存',
        message: switch (error.code) {
          'exists' => '所选位置已有同名文件，请选择其他名称',
          'cleanup_failed' => '保存失败，部分文件未能清理，请在所选位置删除',
          'unsupported_destination' => '请选择本机文件保存位置',
          _ => '文件保存失败，请检查保存位置和权限',
        },
      );
    } on Object {
      throw const UiError(
        code: UbaaErrorCode.invalidInput,
        title: '文件未保存',
        message: '文件保存失败，请检查保存位置和权限',
      );
    }
  }

  Future<void> _deliverOhos(bool Function() current) async {
    final target = await SystemBhpanFileSaver.channel.invokeMethod<String>(
      'resolveFile',
      {'selection': selection},
    );
    if (target == null)
      throw PlatformException(code: 'unsupported_destination');
    if (!current()) throw _sessionChanged;
    final output = File(target);
    try {
      await output.create(exclusive: true);
    } on PathExistsException {
      throw PlatformException(code: 'exists');
    }
    try {
      if (!current()) throw _sessionChanged;
      await _writeOhosFile(output);
    } on Object {
      try {
        await output.delete();
      } on PathNotFoundException {
        // 目标已不存在，无需清理。
      } on FileSystemException {
        throw PlatformException(code: 'cleanup_failed');
      }
      rethrow;
    }
  }

  Future<void> _writeOhosFile(File output) async {
    final source = await File(path).open();
    try {
      final writer = await output.open(mode: FileMode.writeOnly);
      try {
        while (true) {
          final chunk = await source.read(64 * 1024);
          if (chunk.isEmpty) break;
          await writer.writeFrom(chunk);
        }
      } finally {
        await writer.close();
      }
    } finally {
      await source.close();
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
