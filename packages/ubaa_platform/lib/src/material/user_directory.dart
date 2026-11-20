import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 只查询当前系统用户目录，不采用可被进程环境覆盖的 HOME/USERPROFILE。
Directory systemMaterialDirectory() {
  if (Platform.isWindows) {
    return using((arena) {
      final handle = arena<Pointer>();
      // 空令牌会让 Shell 使用进程的 USERPROFILE；显式指定系统用户。
      final opened = OpenProcessToken(
        GetCurrentProcess(),
        TOKEN_QUERY | TOKEN_IMPERSONATE | TOKEN_DUPLICATE,
        handle,
      );
      if (!opened.value) throw const FileSystemException();
      final token = HANDLE(handle.value);
      try {
        final result = arena<Pointer<Utf16>>();
        try {
          final status = _getKnownFolderPath(
            FOLDERID_LocalAppData.toNative(allocator: arena),
            0,
            token,
            result,
          );
          if (status < 0 || result.value == nullptr) {
            throw const FileSystemException();
          }
          return Directory(
            '${result.value.toDartString()}/UBAA/material_coordination_v1',
          );
        } finally {
          CoTaskMemFree(result.value);
        }
      } finally {
        token.close();
      }
    });
  }
  if (!Platform.isMacOS && !Platform.isLinux) throw const FileSystemException();
  final libc = DynamicLibrary.process();
  final uid = libc.lookupFunction<Uint32 Function(), int Function()>(
    'geteuid',
  )();
  final lookup = libc
      .lookupFunction<
        Int32 Function(
          Uint32,
          Pointer<Void>,
          Pointer<Uint8>,
          Size,
          Pointer<Pointer<Void>>,
        ),
        int Function(
          int,
          Pointer<Void>,
          Pointer<Uint8>,
          int,
          Pointer<Pointer<Void>>,
        )
      >('getpwuid_r');
  final home = using((arena) {
    final record = arena.allocate<Void>(
      Platform.isMacOS ? sizeOf<_DarwinUser>() : sizeOf<_LinuxUser>(),
    );
    final buffer = arena<Uint8>(65536);
    final result = arena<Pointer<Void>>();
    if (lookup(uid, record, buffer, 65536, result) != 0 ||
        result.value == nullptr) {
      throw const FileSystemException();
    }
    final path = Platform.isMacOS
        ? record.cast<_DarwinUser>().ref.directory
        : record.cast<_LinuxUser>().ref.directory;
    if (path == nullptr) throw const FileSystemException();
    final bytes = <int>[];
    for (var i = 0; i < 65536; i++) {
      if (path[i] == 0) return utf8.decode(bytes);
      bytes.add(path[i]);
    }
    throw const FileSystemException();
  });
  if (home.isEmpty || !File(home).isAbsolute) throw const FileSystemException();
  return Directory(
    Platform.isMacOS
        ? '$home/Library/Application Support/UBAA/material_coordination_v1'
        : '$home/.local/share/UBAA/material_coordination_v1',
  );
}

// Shell 失败时也可能交回须释放的路径；直接持有输出指针。
final _getKnownFolderPath = DynamicLibrary.open('shell32.dll')
    .lookupFunction<
      Int32 Function(Pointer<GUID>, Uint32, Pointer, Pointer<Pointer<Utf16>>),
      int Function(Pointer<GUID>, int, Pointer, Pointer<Pointer<Utf16>>)
    >('SHGetKnownFolderPath');

/// 布局分别来自锁定 SDK pwd.h 与 Linux libc 的 struct passwd。
final class _LinuxUser extends Struct {
  external Pointer<Uint8> name;
  external Pointer<Uint8> password;
  @Uint32()
  external int uid;
  @Uint32()
  external int gid;
  external Pointer<Uint8> gecos;
  external Pointer<Uint8> directory;
  external Pointer<Uint8> shell;
}

final class _DarwinUser extends Struct {
  external Pointer<Uint8> name;
  external Pointer<Uint8> password;
  @Uint32()
  external int uid;
  @Uint32()
  external int gid;
  @Long()
  external int change;
  external Pointer<Uint8> userClass;
  external Pointer<Uint8> gecos;
  external Pointer<Uint8> directory;
  external Pointer<Uint8> shell;
  @Long()
  external int expire;
}
