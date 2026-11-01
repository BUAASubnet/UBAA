import 'dart:math';
import 'dart:io';
import 'material_coordination.dart';

/// 系统安全存储传输；测试注入不改变生产实现的安全边界。
abstract interface class SecureMaterialTransport {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 原生异常只归约为稳定类别，不暴露密钥、凭据、平台路径或正文。
class SecureMaterialException implements Exception {
  const SecureMaterialException();
  @override
  String toString() => '系统安全存储暂不可用';
}

/// 跨进程协调失败；uncertain 表示必须保留材料并阻止后续恢复。
final class SecureMaterialCoordinationException
    extends SecureMaterialException {
  const SecureMaterialCoordinationException(this.uncertain);
  final bool uncertain;
  @override
  String toString() => uncertain ? '安全材料事务未完成，已阻止后续访问' : '安全材料协调暂不可用';
}

/// 不提供内存、文件或明文降级；材料只在调用期经过 Dart 内存。
class SecureMaterialStore {
  SecureMaterialStore({
    required SecureMaterialTransport transport,
    required this.coordinator,
  }) : _transport = transport;
  final MaterialCoordinator coordinator;

  /// 账号多步骤操作借用同一保护；回调仅可进行短本机操作。
  Future<T> coordinate<T>(Future<T> Function() action) async {
    try {
      return await coordinator.run(action);
    } on MaterialCoordinationException catch (error) {
      throw SecureMaterialCoordinationException(error.uncertain);
    } on FileSystemException {
      throw const SecureMaterialCoordinationException(true);
    } on FormatException {
      throw const SecureMaterialCoordinationException(true);
    }
  }

  final SecureMaterialTransport _transport;
  bool _available = false;
  bool get isAvailable => _available;
  static const _prefix = 'ubaa.material.v2.';

  static const _capabilityValue = 'probe-ok';

  /// 用专用非敏感键闭环验证写入、读回和删除，不枚举或读取用户凭据。
  Future<void> probe() async {
    final suffix = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final capabilityKey = '${_prefix}capability.$suffix';
    try {
      await coordinate(() async {
        await coordinator.beforeMutation();
        try {
          await _transport.write(capabilityKey, _capabilityValue);
          if (await _transport.read(capabilityKey) != _capabilityValue) {
            throw const SecureMaterialException();
          }
          await _transport.delete(capabilityKey);
          if (await _transport.read(capabilityKey) != null) {
            throw const SecureMaterialException();
          }
          _available = true;
        } on Object {
          _available = false;
          try {
            await _transport.delete(capabilityKey);
          } on Object {
            // 保留未完成标记，不用清理回执推断原写入已停止。
          }
          rethrow;
        }
      });
    } on Object {
      _available = false;
    }
  }

  Future<String?> read(String key) => coordinate(() async {
    _validateKey(key);
    try {
      final value = await _transport.read('$_prefix$key');
      if (value != null && value.length > 65536) {
        throw const SecureMaterialException();
      }
      return value;
    } on Object {
      throw const SecureMaterialException();
    }
  });

  Future<void> write(String key, String value) => coordinate(() async {
    _validateKey(key);
    if (value.length > 65536) throw const SecureMaterialException();
    try {
      await coordinator.beforeMutation();
      await _transport.write('$_prefix$key', value);
      // 原生 API 无错误返回仍需确认实际可读，防止权限/签名问题静默丢失。
      if (await _transport.read('$_prefix$key') != value) {
        throw const SecureMaterialException();
      }
    } on Object {
      throw const SecureMaterialException();
    }
  });

  Future<void> delete(String key) => coordinate(() async {
    _validateKey(key);
    try {
      await coordinator.beforeMutation();
      await _transport.delete('$_prefix$key');
      if (await _transport.read('$_prefix$key') != null) {
        throw const SecureMaterialException();
      }
    } on Object {
      throw const SecureMaterialException();
    }
  });

  void _validateKey(String key) {
    if (!_available ||
        key.isEmpty ||
        key.length > 256 ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(key)) {
      throw const SecureMaterialException();
    }
  }
}
