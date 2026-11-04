import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class BhpanFilePicker {
  Future<BhpanLocalFile?> pick();
}

/// 只交付所选文件的本机位置与名称，文件内容由 Core 有界读取。
final class SystemBhpanFilePicker implements BhpanFilePicker {
  const SystemBhpanFilePicker({this.operatingSystem});
  final String? operatingSystem;
  @override
  Future<BhpanLocalFile?> pick() async {
    try {
      if ((operatingSystem ?? Platform.operatingSystem) == 'ohos') {
        const channel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');
        final selected = await channel.invokeMapMethod<String, Object>(
          'pickFile',
        );
        if (selected == null) return null;
        final path = selected['path'] as String,
            name = selected['name'] as String;
        var released = false;
        return BhpanLocalFile(
          path: path,
          name: name,
          release: () async {
            if (!released) {
              released = true;
              await channel.invokeMethod<void>('releaseFile', {'path': path});
            }
          },
        );
      }
      final file = await selector.openFile();
      if (file == null) return null;
      return BhpanLocalFile(path: file.path, name: file.name);
    } on Object {
      throw const UiError(
        code: UbaaErrorCode.unsupported,
        title: '文件选择不可用',
        message: '当前平台无法选择本机文件，请检查文件访问权限',
      );
    }
  }
}
