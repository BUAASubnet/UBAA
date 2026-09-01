import 'package:meta/meta.dart';

/// 一次登录操作使用的账号和密码。
///
/// 该类型只在内存中承载凭据。它不会实现序列化，也不会在
/// [toString]、调试输出或异常文本中暴露字段内容。生产实现应把值交给
/// 系统 Keychain/Keystore，并在请求完成后尽快释放引用。
@immutable
class Credential {
  const Credential({required this.username, required this.password});

  final String username;
  final String password;

  /// 是否满足最小输入要求。
  bool get isUsable => username.trim().isNotEmpty && password.isNotEmpty;

  Credential copyWith({String? username, String? password}) => Credential(
    username: username ?? this.username,
    password: password ?? this.password,
  );

  @override
  String toString() => 'Credential(username: [REDACTED], password: [REDACTED])';

  @override
  bool operator ==(Object other) =>
      other is Credential &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(username, password);
}

/// 兼容调用方常用的复数命名。
typedef Credentials = Credential;

/// 兼容旧调用方的存储值命名。
typedef StoredCredential = Credential;

/// 凭据保险箱的失败类别。
enum CredentialVaultErrorCode { invalidCredential, unavailable, storageFailure }

/// 凭据保险箱错误。
///
/// 错误文本只包含稳定类别，不包含账号、密码、平台异常正文或密钥链内容。
class CredentialVaultException implements Exception {
  const CredentialVaultException(this.code);

  final CredentialVaultErrorCode code;

  String get message => switch (code) {
    CredentialVaultErrorCode.invalidCredential => '凭据输入无效',
    CredentialVaultErrorCode.unavailable => '安全凭据存储不可用',
    CredentialVaultErrorCode.storageFailure => '安全凭据存储操作失败',
  };

  @override
  String toString() => 'CredentialVaultException(${code.name})';
}

/// 平台安全凭据存储的最小接口。
///
/// 接口不规定具体插件。Android 应使用 Keystore，iOS/macOS 应使用
/// Keychain，桌面或测试环境可以注入回调或 [MemoryCredentialVault]。宿主不应
/// 直接读取 session 文件、Cookie 或 Core 内部令牌。
abstract class CredentialVault {
  const CredentialVault();

  /// 创建明确禁用持久化的保险箱。
  factory CredentialVault.noop() => const NoopCredentialVault();

  /// 创建仅供测试使用的内存保险箱。
  factory CredentialVault.memory({Credential? initial}) =>
      MemoryCredentialVault(initial: initial);

  /// 创建只在当前进程存活期间保存凭据的保险箱。
  factory CredentialVault.sessionOnly({Credential? initial}) =>
      SessionOnlyCredentialVault(initial: initial);

  /// 当前平台是否具备持久化能力。
  bool get isAvailable;

  /// 读取最近一次保存的凭据；没有值时返回 `null`。
  Future<Credential?> load();

  /// 保存凭据。实现必须在落盘或发送给平台前校验 [credential]。
  Future<void> save(Credential credential);

  /// 清除凭据及平台存储中的对应条目。
  Future<void> clear();

  /// `load` 的语义别名，便于平台适配层使用。
  Future<Credential?> read() => load();

  /// `save` 的语义别名，便于平台适配层使用。
  Future<void> write(Credential credential) => save(credential);

  /// `clear` 的语义别名，便于平台适配层使用。
  Future<void> delete() => clear();

  /// 以字段形式保存登录凭据的便捷方法。
  Future<void> saveCredentials({
    required String username,
    required String password,
  }) => save(Credential(username: username, password: password));

  /// `load` 的字段命名别名。
  Future<Credential?> loadCredentials() => load();

  /// `clear` 的字段命名别名。
  Future<void> clearCredentials() => clear();

  /// 供所有实现复用的输入校验。
  static void validate(Credential credential) {
    if (!credential.isUsable) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.invalidCredential,
      );
    }
  }
}

/// 明确不保存任何凭据的实现。
///
/// 这是安全默认值：调用 [save] 会成功返回但不会持久化，调用 [load] 始终
/// 返回 `null`。UI 应通过 [CredentialVault.isAvailable] 决定是否显示“记住
/// 密码”选项，不能把成功返回解释为已保存。
class NoopCredentialVault extends CredentialVault {
  const NoopCredentialVault();

  @override
  bool get isAvailable => false;

  @override
  Future<Credential?> load() async => null;

  @override
  Future<void> save(Credential credential) async {
    CredentialVault.validate(credential);
  }

  @override
  Future<void> clear() async {}
}

/// 测试用的内存保险箱；不会写入文件或系统安全存储。
class MemoryCredentialVault extends CredentialVault {
  MemoryCredentialVault({Credential? initial}) : _credential = initial {
    if (initial != null) CredentialVault.validate(initial);
  }

  Credential? _credential;
  int _saveCount = 0;
  int _clearCount = 0;

  @override
  bool get isAvailable => true;

  /// 当前是否有凭据，仅供测试断言，不返回秘密值。
  bool get hasValue => _credential != null;

  /// 保存调用次数，仅供测试断言。
  int get saveCount => _saveCount;

  /// 清除调用次数，仅供测试断言。
  int get clearCount => _clearCount;

  @override
  Future<Credential?> load() async => _credential?.copyWith();

  @override
  Future<void> save(Credential credential) async {
    CredentialVault.validate(credential);
    _credential = credential.copyWith();
    _saveCount++;
  }

  @override
  Future<void> clear() async {
    _credential = null;
    _clearCount++;
  }
}

/// 只在当前进程内保留凭据的实现。
///
/// 与测试用 [MemoryCredentialVault] 相同，进程结束即丢失；`isAvailable` 为
/// `false`，因此 UI 不应把它宣称为系统级“记住密码”。
class SessionOnlyCredentialVault extends MemoryCredentialVault {
  SessionOnlyCredentialVault({super.initial});

  @override
  bool get isAvailable => false;
}

typedef CredentialLoader = Future<Credential?> Function();
typedef CredentialSaver = Future<void> Function(Credential credential);
typedef CredentialClearer = Future<void> Function();

/// 由原生插件实现的系统安全存储。
///
/// 插件必须把值放入当前平台的 Keychain、Keystore、Credential Manager、
/// Secret Service 或 HUKS；本接口不提供文件或明文降级实现。
abstract interface class PlatformSecureCredentialStore {
  bool get isAvailable;

  Future<Credential?> read(String namespace);

  Future<void> write(String namespace, Credential credential);

  Future<void> clear(String namespace);
}

/// 版本化命名空间的原生安全存储适配器。
///
/// 该类只负责能力检查、输入校验和稳定错误归约；具体平台实现通过
/// [PlatformSecureCredentialStore] 注入，避免应用层接触平台密钥或密文。
class PlatformCredentialVault extends CredentialVault {
  PlatformCredentialVault({
    required PlatformSecureCredentialStore store,
    this.namespace = 'com.buaa.ubaa.credentials.v1',
  }) : _store = store;

  final PlatformSecureCredentialStore _store;
  final String namespace;

  @override
  bool get isAvailable => _store.isAvailable;

  @override
  Future<Credential?> load() async {
    if (!isAvailable) return null;
    try {
      final credential = await _store.read(namespace);
      if (credential == null) return null;
      CredentialVault.validate(credential);
      return credential.copyWith();
    } catch (_) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }

  @override
  Future<void> save(Credential credential) async {
    CredentialVault.validate(credential);
    if (!isAvailable) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.unavailable,
      );
    }
    try {
      await _store.write(namespace, credential.copyWith());
    } catch (_) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }

  @override
  Future<void> clear() async {
    if (!isAvailable) return;
    try {
      await _store.clear(namespace);
    } catch (_) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }
}

/// 由 Flutter 平台插件注入的回调实现。
///
/// 回调内部负责调用 Keychain/Keystore；本类只做输入校验和能力声明，不会
/// 记录或复制异常正文。
class CallbackCredentialVault extends CredentialVault {
  CallbackCredentialVault({
    required CredentialLoader loader,
    required CredentialSaver saver,
    required CredentialClearer clearer,
    bool available = true,
  }) : _loader = loader,
       _saver = saver,
       _clearer = clearer,
       _available = available;

  final CredentialLoader _loader;
  final CredentialSaver _saver;
  final CredentialClearer _clearer;
  final bool _available;

  @override
  bool get isAvailable => _available;

  @override
  Future<Credential?> load() async {
    if (!_available) return null;
    try {
      return await _loader();
    } catch (_) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }

  @override
  Future<void> save(Credential credential) async {
    CredentialVault.validate(credential);
    if (!_available) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.unavailable,
      );
    }
    try {
      await _saver(credential);
    } catch (_) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }

  @override
  Future<void> clear() async {
    if (!_available) return;
    try {
      await _clearer();
    } catch (_) {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }
}
