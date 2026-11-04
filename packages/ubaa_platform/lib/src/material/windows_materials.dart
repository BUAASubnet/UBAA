import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'secure_material_core.dart';

abstract interface class WindowsMaterialCodec {
  Uint8List decrypt(Uint8List ciphertext);
  Uint8List encrypt(Uint8List plaintext);
}

/// 保留 flutter_secure_storage_windows 4.1.0 的文件名、DPAPI 编码和材料键。
/// 读取无迁移副作用；损坏、未知条目或读取失败均保留原件并明确失败。
/// 所有调用由外层 SecureMaterialStore 的同域事务保护。
final class WindowsFileMaterials implements SecureMaterialTransport {
  WindowsFileMaterials({required this.file, required this.codec, this.replace});
  final Future<File> Function() file;
  final WindowsMaterialCodec codec;
  final Future<void> Function(File pending, File target)? replace;

  Future<Map<String, String>> _load(File source) async {
    final type = await FileSystemEntity.type(source.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound)
      throw const SecureMaterialException();
    late Uint8List ciphertext;
    try {
      ciphertext = await source.readAsBytes();
    } on FileSystemException catch (error) {
      // type() 也会把查询错误归为 notFound，只有明确的 OS 缺失错误可建空库。
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) return {};
      rethrow;
    }
    final plain = codec.decrypt(ciphertext);
    try {
      final value = jsonDecode(utf8.decode(plain));
      if (value is! Map<String, dynamic> ||
          value.values.any((v) => v is! String)) {
        throw const SecureMaterialException();
      }
      return value.cast<String, String>();
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  Future<void> _save(File target, Map<String, String> values) async {
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(values)));
    late Uint8List encrypted;
    try {
      encrypted = codec.encrypt(plain);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
    await target.parent.create(recursive: true);
    final suffix = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final pending = File('${target.path}.$suffix.pending');
    try {
      await pending.writeAsBytes(encrypted, flush: true);
      // 同目录替换。加密或临时文件写入失败不会截断既有材料；不自动重试。
      if (replace != null) {
        await replace!(pending, target);
      } else {
        await pending.rename(target.path);
      }
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  @override
  Future<String?> read(String key) async => (await _load(await file()))[key];
  @override
  Future<void> write(String key, String value) async {
    final target = await file();
    final values = await _load(target);
    values[key] = value;
    await _save(target, values);
  }

  @override
  Future<void> delete(String key) async {
    final target = await file();
    final values = await _load(target);
    if (values.remove(key) != null) await _save(target, values);
  }
}
