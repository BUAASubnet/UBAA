import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'secure_material_core.dart';
import 'windows_materials.dart';

/// 已有文件使用 ReplaceFileW 合并原安全描述符。失败保留密文备份，交由
/// 未完成事务阻断后续操作，不抹备份、不自动重试或恢复。
Future<void> replaceWindowsMaterial(
  File pending,
  File target, {
  ({int attributes, int errorCode}) Function(File) queryTarget =
      _queryWindowsMaterial,
  int Function(File, File, int) moveNew = _moveWindowsMaterial,
  int Function(File, File, File, int) replaceExisting = _replaceWindowsMaterial,
}) async {
  final query = queryTarget(target);
  if (query.attributes == 0xffffffff) {
    if (query.errorCode != ERROR_FILE_NOT_FOUND &&
        query.errorCode != ERROR_PATH_NOT_FOUND) {
      throw const SecureMaterialException();
    }
    // 不带 REPLACE_EXISTING。查询后目标出现就失败，不回退或重试。
    if (moveNew(pending, target, MOVEFILE_WRITE_THROUGH) == 0) {
      throw const SecureMaterialException();
    }
    return;
  }
  if (query.attributes &
          (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) !=
      0) {
    throw const SecureMaterialException();
  }
  final backup = File('${pending.path}.previous');
  if (replaceExisting(pending, target, backup, 0) == 0) {
    throw const SecureMaterialException();
  }
  if (await backup.exists()) await backup.delete();
}

({int attributes, int errorCode}) _queryWindowsMaterial(File target) {
  final attributes = using(
    (arena) => GetFileAttributes(
      PCWSTR(target.path.toNativeUtf16(allocator: arena)),
    ).value,
  );
  if (attributes != 0xffffffff) return (attributes: attributes, errorCode: 0);

  // Dart FFI 的两次调用之间可能丢失 Win32 错误码。用只读打开获取
  // Dart I/O 保留的系统错误；属性查询失败时仍不允许替换现有文件。
  final RandomAccessFile handle;
  try {
    handle = target.openSync();
  } on FileSystemException catch (error) {
    return (attributes: attributes, errorCode: error.osError?.errorCode ?? 0);
  }
  handle.closeSync();
  return (attributes: attributes, errorCode: 0);
}

int _moveWindowsMaterial(File pending, File target, int flags) => using(
  (arena) =>
      MoveFileEx(
        PCWSTR(pending.path.toNativeUtf16(allocator: arena)),
        PCWSTR(target.path.toNativeUtf16(allocator: arena)),
        MOVE_FILE_FLAGS(flags),
      ).value
      ? 1
      : 0,
);

int _replaceWindowsMaterial(File pending, File target, File backup, int flags) {
  final replace = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Uint32,
          Pointer<Void>,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
          Pointer<Void>,
          Pointer<Void>,
        )
      >('ReplaceFileW');
  return using(
    (arena) => replace(
      target.path.toNativeUtf16(allocator: arena),
      pending.path.toNativeUtf16(allocator: arena),
      backup.path.toNativeUtf16(allocator: arena),
      flags,
      nullptr,
      nullptr,
    ),
  );
}

/// 与锁定 Windows 插件相同的用户级 DPAPI：无 entropy，flags=0。
final class WindowsDpapiCodec implements WindowsMaterialCodec {
  const WindowsDpapiCodec();
  Uint8List _convert(Uint8List bytes, {required bool encrypting}) => using((
    arena,
  ) {
    final input = arena<CRYPT_INTEGER_BLOB>();
    final output = arena<CRYPT_INTEGER_BLOB>();
    input.ref.cbData = bytes.length;
    input.ref.pbData = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    input.ref.pbData.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final status = encrypting
          ? CryptProtectData(input, null, null, null, 0, output)
          : CryptUnprotectData(input, null, null, null, 0, output);
      if (!status.value || output.ref.pbData == nullptr)
        throw const SecureMaterialException();
      return Uint8List.fromList(
        output.ref.pbData.asTypedList(output.ref.cbData),
      );
    } finally {
      input.ref.pbData.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      if (output.ref.pbData != nullptr) {
        output.ref.pbData
            .asTypedList(output.ref.cbData)
            .fillRange(0, output.ref.cbData, 0);
        LocalFree(HLOCAL(output.ref.pbData));
      }
    }
  });
  @override
  Uint8List decrypt(Uint8List ciphertext) =>
      _convert(ciphertext, encrypting: false);
  @override
  Uint8List encrypt(Uint8List plaintext) =>
      _convert(plaintext, encrypting: true);
}
