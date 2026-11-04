import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'secure_material_core.dart';

/// GUI 与无图形会话共用同一个 Secret Service item 和 JSON map。
/// 材料事务锁由 SecureMaterialStore 持有，FFI 在工作 isolate 中执行。
final class LinuxSecretServiceTransport implements SecureMaterialTransport {
  LinuxSecretServiceTransport({String? library})
    : library =
          library ??
          '${File(Platform.resolvedExecutable).parent.path}/lib/libubaa_command_materials.so';
  final String library;
  Future<Map<String, dynamic>> _read() async {
    final raw = await Isolate.run(() => _call(library, 0, null));
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value.values.any((v) => v is! String))
      throw const SecureMaterialException();
    return value;
  }

  @override
  Future<String?> read(String key) async => (await _read())[key] as String?;
  @override
  Future<void> write(String key, String value) async {
    final values = await _read();
    values[key] = value;
    await Isolate.run(() => _call(library, 1, jsonEncode(values)));
  }

  @override
  Future<void> delete(String key) async {
    final values = await _read();
    if (!values.containsKey(key)) return;
    values.remove(key);
    await Isolate.run(() => _call(library, 1, jsonEncode(values)));
  }
}

String _call(String library, int operation, String? value) {
  try {
    return using((arena) {
      final native = DynamicLibrary.open(library);
      final call = native
          .lookupFunction<
            Int32 Function(Int32, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
            int Function(int, Pointer<Utf8>, Pointer<Pointer<Utf8>>)
          >('ubaa_command_materials');
      final release = native
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('ubaa_command_materials_free');
      final output = arena<Pointer<Utf8>>();
      try {
        final status = call(
          operation,
          value?.toNativeUtf8(allocator: arena) ?? nullptr,
          output,
        );
        if (status != 0) throw const SecureMaterialException();
        return output.value == nullptr ? '{}' : output.value.toDartString();
      } finally {
        if (output.value != nullptr) release(output.value);
      }
    });
  } on Object {
    throw const SecureMaterialException();
  }
}
