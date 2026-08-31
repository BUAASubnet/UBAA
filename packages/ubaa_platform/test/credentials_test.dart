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
  });
}
