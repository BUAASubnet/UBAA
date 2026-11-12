import 'dart:io';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import 'bhpan_download.dart';

const _printExtensions = [
  'jpg',
  'jpeg',
  'heic',
  'png',
  'pdf',
  'txt',
  'doc',
  'xls',
  'xslx',
  'ppt',
  'docx',
  'xlsx',
  'pptx',
  'wps',
  'wpt',
  'dot',
  'rtf',
  'dotx',
  'docm',
  'dotm',
  'xml',
  'mht',
  'mhtml',
  'html',
  'htm',
  'xps',
  'odt',
  'xlsm',
  'xlsb',
  'csv',
  'xltx',
  'xltm',
  'xlt',
  'prn',
  'dif',
  'slk',
  'xla',
  'xlam',
  'ods',
  'dps',
  'dpt',
  'pot',
  'pps',
  'pptm',
  'potm',
  'ppsm',
];

const _fileChannel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');
const _changed = UiError(
  code: UbaaErrorCode.operationConflict,
  title: '登录状态已变化',
  message: '已停止保存剩余文件',
);
const _saveError = UiError(
  code: UbaaErrorCode.invalidInput,
  title: '文件未保存',
  message: '请检查存储空间和文件夹访问权限',
);

final class SystemCloudPrintFiles {
  const SystemCloudPrintFiles();

  Future<List<PrintSource>> pick() async {
    try {
      if (Platform.isAndroid || Platform.operatingSystem == 'ohos') {
        final files = await _fileChannel
            .invokeListMethod<Map<Object?, Object?>>('pickFiles', {
              'extensions': _printExtensions,
            });
        return [
          for (final file in files ?? const [])
            PrintSource(
              path: file['path']! as String,
              name: file['name']! as String,
              release: () => _fileChannel.invokeMethod<void>('releaseFile', {
                'path': file['path'],
              }),
            ),
        ];
      }
      final files = await selector.openFiles(
        acceptedTypeGroups: const [
          selector.XTypeGroup(
            label: '官网列出的打印格式',
            extensions: _printExtensions,
            uniformTypeIdentifiers: [
              'com.adobe.pdf',
              'public.jpeg',
              'public.png',
              'public.heic',
              'public.plain-text',
              'public.comma-separated-values-text',
              'public.rtf',
              'public.xml',
              'public.html',
              'com.microsoft.word.doc',
              'com.microsoft.excel.xls',
              'com.microsoft.powerpoint.ppt',
              'org.openxmlformats.wordprocessingml.document',
              'org.openxmlformats.spreadsheetml.sheet',
              'org.openxmlformats.presentationml.presentation',
              'org.oasis-open.opendocument.text',
              'org.oasis-open.opendocument.spreadsheet',
            ],
          ),
        ],
      );
      return [
        for (final file in files) PrintSource(path: file.path, name: file.name),
      ];
    } on PlatformException catch (error) {
      if (error.code == 'too_many') {
        throw const UiError(
          code: UbaaErrorCode.invalidInput,
          title: '文件数量过多',
          message: '每批最多上传 20 份，请分批选择',
        );
      }
      throw _pickError;
    } on Object {
      throw _pickError;
    }
  }

  static const _pickError = UiError(
    code: UbaaErrorCode.unsupported,
    title: '无法选择文件',
    message: '请检查本机文件访问权限',
  );

  Future<PrintDownloadFolder?> pickFolder(bool Function() current) async {
    if (!current()) return null;
    try {
      final os = Platform.operatingSystem;
      if (os == 'android' || os == 'ios') {
        final token = await _fileChannel.invokeMethod<String>('selectFolder');
        if (token == null) return null;
        final folder = _NativePrintFolder(token);
        if (current()) return folder;
        await folder.close();
        return null;
      }
      final path = os == 'ohos'
          ? await _fileChannel.invokeMethod<String>('pickFolder')
          : await selector.getDirectoryPath();
      if (path == null || !current()) return null;
      return LocalPrintDownloadFolder(Directory(path));
    } on Object {
      throw const UiError(
        code: UbaaErrorCode.unsupported,
        title: '无法选择保存目录',
        message: '请选择可写入的本机文件夹',
      );
    }
  }

  bool get canRenderPdf => Platform.isAndroid || Platform.isWindows;

  Future<PrintPdfPage> renderPdf(
    Uint8List bytes,
    int page,
    bool Function() current,
  ) async {
    Directory? staging;
    try {
      if (!current()) throw _changed;
      staging = await (await getTemporaryDirectory()).createTemp(
        'ubaa-scan-preview-',
      );
      final file = File.fromUri(staging.uri.resolve('document.pdf'));
      await file.writeAsBytes(bytes, flush: true);
      if (!current()) throw _changed;
      final result = await _fileChannel.invokeMapMethod<String, Object>(
        'renderScanPdf',
        {'path': file.path, 'page': page},
      );
      if (!current()) throw _changed;
      return (
        totalPages: result!['totalPages']! as int,
        image: result['image']! as Uint8List,
      );
    } on PlatformException {
      throw const UiError(
        code: UbaaErrorCode.unsupported,
        title: '无法预览扫描 PDF',
        message: '请尝试下载后打开该文件',
      );
    } finally {
      if (staging != null) await staging.delete(recursive: true);
    }
  }

  bool get canPreviewPdf => Platform.isIOS;

  Future<void> previewPdf(Uint8List bytes, bool Function() current) async {
    final destination = await const SystemBhpanFilePreviewer().select(
      '扫描文档.pdf',
      current,
    );
    if (destination == null) return;
    try {
      await File(destination.path).writeAsBytes(bytes, flush: true);
      if (!current()) throw _changed;
      await destination.deliver(current);
    } on FileSystemException {
      throw _saveError;
    } finally {
      await destination.discard();
    }
  }
}

String _safeName(String name) {
  var safe = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .trim()
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (safe.isEmpty) safe = '扫描文档';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[0-9¹²³]|LPT[0-9¹²³])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(safe)) {
    safe = '_$safe';
  }
  return safe;
}

/// A local filesystem path from the desktop or HarmonyOS system folder picker.
final class LocalPrintDownloadFolder implements PrintDownloadFolder {
  const LocalPrintDownloadFolder(this.directory);
  final Directory directory;

  @override
  Future<String> save(
    String name,
    Uint8List bytes,
    bool Function() current,
  ) async {
    final safe = _safeName(name);
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final extension = dot > 0 ? safe.substring(dot) : '';
    for (var suffix = 0; suffix < 10000; suffix++) {
      if (!current()) throw _changed;
      final candidate = suffix == 0 ? safe : '$base ($suffix)$extension';
      final output = File.fromUri(
        directory.uri.resolveUri(Uri(pathSegments: [candidate])),
      );
      try {
        await output.create(exclusive: true);
      } on PathExistsException {
        continue;
      } on FileSystemException {
        throw _saveError;
      }
      try {
        if (!current()) throw _changed;
        await output.writeAsBytes(bytes, flush: true);
        return candidate;
      } on Object catch (error) {
        try {
          await output.delete();
        } on FileSystemException {
          throw _saveError;
        }
        if (error is UiError) rethrow;
        throw _saveError;
      }
    }
    throw _saveError;
  }

  @override
  Future<void> close() async {}
}

final class _NativePrintFolder implements PrintDownloadFolder {
  const _NativePrintFolder(this.token);
  final String token;

  @override
  Future<String> save(
    String name,
    Uint8List bytes,
    bool Function() current,
  ) async {
    Directory? staging;
    try {
      if (!current()) throw _changed;
      staging = await (await getTemporaryDirectory()).createTemp('ubaa-scan-');
      final file = File.fromUri(staging.uri.resolve('document'));
      await file.writeAsBytes(bytes, flush: true);
      if (!current()) throw _changed;
      final savedName = await _fileChannel.invokeMethod<String>(
        'writeFolderFile',
        {'selection': token, 'name': _safeName(name), 'path': file.path},
      );
      if (savedName == null) throw _saveError;
      return savedName;
    } on PlatformException {
      throw _saveError;
    } on FileSystemException {
      throw _saveError;
    } finally {
      if (staging != null) await staging.delete(recursive: true);
    }
  }

  @override
  Future<void> close() =>
      _fileChannel.invokeMethod<void>('discardFolder', {'selection': token});
}
