import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/contracts/session_recovery.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/materials.dart';
import 'package:ubaa_test_support/recovery.dart' show MemoryMaterials;

void main() {
  const user = 'fixture-user';
  final superseded = isA<RecoveryInterrupted>().having(
    (error) => error.reason,
    '中断原因',
    RecoveryStopReason.superseded,
  );
  late SecureLocalAccountStore accounts;
  setUp(() async {
    final materials = syntheticMaterials(MemoryMaterials());
    await materials.probe();
    accounts = SecureLocalAccountStore(materials);
  });

  Future<SharedAccountBinding> bind({bool retainSession = false}) async {
    await accounts.retain(user, retainSession: retainSession);
    return accounts.bindSnapshot(
      (await accounts.capture())!,
      requireRestore: false,
    );
  }

  RecoveryScope scope(SharedAccountBinding binding, bool Function() current) =>
      RecoveryScope.currentSession(
        binding: binding,
        routeGeneration: 1,
        backendGeneration: 2,
        credentialGeneration: 3,
        routePolicy: RoutePolicy.direct,
        publishReusedSession: true,
        isCurrent: current,
      );

  test('D7 当前会话只复用绑定身份，不协调恢复、发布或续接', () async {
    final binding = await bind();
    final recovery = scope(binding, () => true);
    expect(recovery.accountAlias, binding.account.id);
    expect(recovery.expectedUsername, user);
    expect(recovery.accountGeneration, binding.generation);
    expect(recovery.routeGeneration, 1);
    expect(recovery.backendGeneration, 2);
    expect(recovery.credentialGeneration, 3);
    expect(recovery.routePolicy, RoutePolicy.direct);
    expect(recovery.publishReusedSession, isTrue);
    expect(recovery.accepts(const UserSummary(username: user)), isTrue);
    expect(
      recovery.accepts(const UserSummary(username: 'another-user')),
      isFalse,
    );
    expect(recovery.acceptsRoute(ConnectionMode.direct), isTrue);
    expect(recovery.acceptsRoute(ConnectionMode.webvpn), isFalse);
    expect(recovery.allowAutomaticLogin, isFalse);
    expect(recovery.isShared, isFalse);
    expect(recovery.sharedSnapshot, same(binding.snapshot));
    await recovery.validatePersistent();
    await recovery.validateSharedState();
    expect(await recovery.coordinateRecovery(() async => 1, () => true), 1);
    var delivered = false;
    await recovery.commitDelivery(() => delivered = true);
    expect(delivered, isTrue);
    expect(await recovery.sharedBinding(), isNull);
    await recovery.publishRecovery();
    expect(await recovery.adoptRecoverySuccessor(), isFalse);
    await recovery.revokeRejectedCredentials();
    expect((await accounts.read())!.generation, binding.generation);
  });

  test('D7 工厂拒绝撤销绑定、保留绑定和已失效授权', () async {
    final binding = await bind();
    expect(() => scope(binding, () => false), throwsA(superseded));
    final revoked = await accounts.revokeBinding(binding.snapshot);
    expect(() => scope(revoked, () => true), throwsA(superseded));
    final retained = await bind(retainSession: true);
    expect(() => scope(retained, () => true), throwsA(superseded));
  });

  for (final external in [false, true]) {
    test('D7 失效授权不能校验或提交交付，索引变更=$external', () async {
      var current = true;
      final recovery = scope(await bind(), () => current);
      if (external) {
        await SecureLocalAccountStore(accounts.materials).signOut();
      } else {
        current = false;
      }
      await expectLater(recovery.validatePersistent(), throwsA(superseded));
      await expectLater(recovery.validateSharedState(), throwsA(superseded));
      await expectLater(
        recovery.commitDelivery(() => fail('不得交付过期结果')),
        throwsA(superseded),
      );
    });
  }
}
