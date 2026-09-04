part of '../ubaa_app_host_test.dart';

void _registerBootstrapTests() {
  test('共享 bootstrap 严格按初始化顺序启动同一宿主', () async {
    final events = <String>[];
    final vault = MemoryCredentialVault();
    final picker = MemoryPhotoPicker();
    final permissions = MemoryPermissionGateway();
    final locations = MemoryLocationProvider();
    Widget? launched;

    await bootstrapUbaaHost(
      ensureFlutterInitialized: () => events.add('binding'),
      initializeSdk: () async {
        events.add('sdk:start');
        await Future<void>.delayed(Duration.zero);
        events.add('sdk:end');
      },
      debugHello: () {
        events.add('hello');
        return 'UBAA FRB 2.13.0 ready';
      },
      createCapabilities: () async {
        events.add('capabilities:start');
        await Future<void>.delayed(Duration.zero);
        events.add('capabilities:end');
        return PlatformCapabilities(
          credentialVault: vault,
          photoPicker: picker,
          permissionGateway: permissions,
          locationProvider: locations,
        );
      },
      runApplication: (app) {
        events.add('runApp');
        launched = app;
      },
    );

    expect(events, <String>[
      'binding',
      'sdk:start',
      'sdk:end',
      'hello',
      'capabilities:start',
      'capabilities:end',
      'runApp',
    ]);
    final host = launched! as UbaaAppHost;
    expect(host.credentialVault, same(vault));
    expect(host.photoPicker, same(picker));
    expect(host.permissionGateway, same(permissions));
    expect(host.locationProvider, same(locations));
  });

  test('SDK 初始化失败时不探测 hello、不创建能力也不运行应用', () async {
    final events = <String>[];
    final failure = StateError('脱敏 SDK 初始化失败');

    await expectLater(
      bootstrapUbaaHost(
        ensureFlutterInitialized: () => events.add('binding'),
        initializeSdk: () async {
          events.add('sdk');
          throw failure;
        },
        debugHello: () {
          events.add('hello');
          return 'UBAA FRB 2.13.0 ready';
        },
        createCapabilities: () async {
          events.add('capabilities');
          return _capabilities();
        },
        runApplication: (_) => events.add('runApp'),
      ),
      throwsA(same(failure)),
    );
    expect(events, <String>['binding', 'sdk']);
  });

  test('debug hello 失败时不创建能力也不运行应用', () async {
    final events = <String>[];

    await expectLater(
      bootstrapUbaaHost(
        ensureFlutterInitialized: () => events.add('binding'),
        initializeSdk: () async => events.add('sdk'),
        debugHello: () {
          events.add('hello');
          return 'unexpected';
        },
        createCapabilities: () async {
          events.add('capabilities');
          return _capabilities();
        },
        runApplication: (_) => events.add('runApp'),
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(events, <String>['binding', 'sdk', 'hello']);
  });
}
