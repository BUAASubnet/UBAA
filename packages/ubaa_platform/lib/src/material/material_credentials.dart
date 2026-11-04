import 'dart:convert';
import '../credentials.dart';
import 'secure_material_core.dart';
import '../local_accounts.dart';

/// 保留旧 autoLogin 授权值；升级不会将关闭状态改为允许提交密码。
final class MaterialCredentialStore implements PlatformSecureCredentialStore {
  MaterialCredentialStore(this.materials);
  final SecureMaterialStore materials;
  Future<void> _revoke(String namespace) async {
    if (namespace != 'com.buaa.ubaa.credentials.v1') return;
    final accounts = SecureLocalAccountStore(materials);
    if (await accounts.read() != null) await accounts.signOut();
  }

  /// 在同一材料事务内核对持久许可和密码所属账号。调用方提交前仍须再验代次。
  Future<Credential?> readForRestore(LocalAccountSnapshot snapshot) =>
      materials.coordinate(() async {
        if (!await SecureLocalAccountStore(materials).validate(snapshot))
          return null;
        final credential = await read('com.buaa.ubaa.credentials.v1');
        if (credential == null ||
            !credential.autoLogin ||
            credential.username.trim() != snapshot.state.account?.username)
          return null;
        return credential;
      });

  @override
  bool get isAvailable => materials.isAvailable;

  @override
  Future<Credential?> read(String namespace) => materials.coordinate(() async {
    try {
      final raw = await materials.read('credentials.$namespace');
      if (raw == null) return null;
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['username'] is! String ||
          value['password'] is! String ||
          value['autoLogin'] is! bool) {
        throw const CredentialVaultException(
          CredentialVaultErrorCode.storageFailure,
        );
      }
      final credential = Credential(
        username: value['username'] as String,
        password: value['password'] as String,
        autoLogin: value['autoLogin'] as bool,
      );
      CredentialVault.validate(credential);
      return credential;
    } on Object {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  });

  @override
  Future<void> write(String namespace, Credential credential) =>
      materials.coordinate(() async {
        CredentialVault.validate(credential);
        try {
          await _revoke(namespace);
          await materials.write(
            'credentials.$namespace',
            jsonEncode({
              'username': credential.username,
              'password': credential.password,
              'autoLogin': credential.autoLogin,
            }),
          );
        } on Object {
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        }
      });

  @override
  Future<void> clear(String namespace) => materials.coordinate(() async {
    try {
      await _revoke(namespace);
      await materials.delete('credentials.$namespace');
    } on Object {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  });
}
