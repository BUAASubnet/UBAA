import 'package:test/test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  group('CredentialVault', () {
    test('内存实现保存、读取和清除凭据', () async {
      final vault = MemoryCredentialVault();
      const credential = Credential(username: 'student', password: 'secret');

      await vault.save(credential);
      expect(vault.isAvailable, isTrue);
      expect(vault.hasValue, isTrue);
      expect(await vault.load(), credential);

      await vault.clear();
      expect(vault.hasValue, isFalse);
      expect(await vault.read(), isNull);
    });

    test('无效凭据不会写入', () async {
      final vault = MemoryCredentialVault();

      expect(
        () => vault.save(const Credential(username: '', password: 'secret')),
        throwsA(
          isA<CredentialVaultException>().having(
            (error) => error.code,
            'code',
            CredentialVaultErrorCode.invalidCredential,
          ),
        ),
      );
      expect(vault.hasValue, isFalse);
      expect(vault.saveCount, 0);
    });

    test('默认无操作实现不保存且不泄露凭据', () async {
      final vault = CredentialVault.noop();
      const credential = Credential(username: 'student', password: 'secret');

      await vault.save(credential);
      expect(vault.isAvailable, isFalse);
      expect(await vault.load(), isNull);
      expect(credential.toString(), isNot(contains('secret')));
      expect(
        const CredentialVaultException(
          CredentialVaultErrorCode.storageFailure,
        ).toString(),
        isNot(contains('secret')),
      );
    });

    test('回调实现隐藏平台异常正文', () async {
      final vault = CallbackCredentialVault(
        loader: () async => throw StateError('password=secret'),
        saver: (_) async {},
        clearer: () async {},
      );

      expect(
        vault.load,
        throwsA(
          isA<CredentialVaultException>().having(
            (error) => error.code,
            'code',
            CredentialVaultErrorCode.storageFailure,
          ),
        ),
      );
    });

    test('平台安全存储适配器使用版本化命名空间且不落明文文件', () async {
      final store = _FakeSecureStore();
      final vault = PlatformCredentialVault(store: store);
      const credential = Credential(username: 'student', password: 'secret');

      await vault.save(credential);
      expect(store.lastNamespace, 'com.buaa.ubaa.credentials.v1');
      expect(await vault.load(), credential);
      await vault.clear();
      expect(await vault.load(), isNull);
    });

    test('平台安全存储不可用时明确退回本次会话', () async {
      final vault = PlatformCredentialVault(
        store: _FakeSecureStore(available: false),
      );
      expect(vault.isAvailable, isFalse);
      expect(
        vault.save(const Credential(username: 'student', password: 'secret')),
        throwsA(
          isA<CredentialVaultException>().having(
            (error) => error.code,
            'code',
            CredentialVaultErrorCode.unavailable,
          ),
        ),
      );
      expect(await vault.load(), isNull);
    });
  });
}

class _FakeSecureStore implements PlatformSecureCredentialStore {
  _FakeSecureStore({this.available = true});

  final bool available;
  Credential? _value;
  String? lastNamespace;

  @override
  bool get isAvailable => available;

  @override
  Future<Credential?> read(String namespace) async {
    lastNamespace = namespace;
    return _value?.copyWith();
  }

  @override
  Future<void> write(String namespace, Credential credential) async {
    lastNamespace = namespace;
    _value = credential.copyWith();
  }

  @override
  Future<void> clear(String namespace) async {
    lastNamespace = namespace;
    _value = null;
  }
}
