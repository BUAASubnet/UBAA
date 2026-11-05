import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/agenda/backend.dart';
import 'package:ubaa_app/src/bridge/auth/session.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_test_support/recovery.dart' show MemoryMaterials;
import 'sync_bridge_test.dart' as fixture;

class _Scope implements BridgeAgendaSyncScope {
  _Scope(this.generation);
  final int generation;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RouteClient extends fixture.Client {
  BridgeRoutePolicy route = BridgeRoutePolicy.direct;
  int generation = 0;

  @override
  BridgeAgendaSyncScope captureAgendaSyncScope() => _Scope(generation);

  final dispatched = <(BridgeRoutePolicy, BridgeAgendaSyncAction)>[];
  SecureMaterialStore? routeMaterials;
  final routeOwnsClient = Completer<void>();
  Future<void>? routeInFlight;

  @override
  Future<BridgeRouteSettings> setDefaultRoutePolicy({
    required BridgeRoutePolicy policy,
  }) async {
    final materials = routeMaterials;
    if (materials != null) {
      // 复现原生路线设置的锁顺序：先拿 Bridge 客户端，再核对共享材料。
      final done = Completer<void>();
      routeInFlight = done.future;
      routeOwnsClient.complete();
      try {
        await materials.coordinate(() async {});
        route = policy;
        generation++;
      } finally {
        routeInFlight = null;
        done.complete();
      }
    } else {
      route = policy;
      generation++;
    }
    return BridgeRouteSettings(
      defaultPolicy: policy,
      activeRoutes: const [
        BridgeConnectionMode.direct,
        BridgeConnectionMode.webVpn,
      ],
    );
  }

  @override
  Future<BridgeAgendaSyncReport> syncAgenda({
    required BridgeAgendaSyncService service,
    required BridgeAgendaSyncAction action,
    required BridgeAgendaTime now,
  }) => _dispatch(action);

  @override
  Future<BridgeAgendaSyncReport> createAgendaSyncConfirmed({
    required BridgeAgendaSyncService service,
    required BridgeAgendaTime now,
    required BridgeAgendaSyncScope scope,
  }) => _dispatch(BridgeAgendaSyncAction.createConfirmed, scope);

  Future<BridgeAgendaSyncReport> _dispatch(
    BridgeAgendaSyncAction action, [
    BridgeAgendaSyncScope? scope,
  ]) async {
    // 原生 sync_agenda 等路线设置释放客户端锁后才取执行客户端。
    await routeInFlight;
    if (action == BridgeAgendaSyncAction.createConfirmed &&
        (scope is! _Scope || scope.generation != generation)) {
      throw const BridgeAgendaSyncError(
        local: BridgeAgendaFailure.superseded,
        remote: null,
      );
    }
    dispatched.add((route, action));
    if (route == BridgeRoutePolicy.webVpn) {
      throw const BridgeAgendaSyncError(
        local: null,
        remote: BridgeError(
          code: BridgeErrorCode.upstreamUnavailable,
          kind: BridgeErrorKind.upstream,
          retryable: false,
          message: '合成 WebVPN 云盘不可用',
          resolvedRoute: null,
          cacheFailure: null,
        ),
      );
    }
    return const BridgeAgendaSyncReport(
      status: BridgeAgendaSyncStatus.needsCreation,
      pendingCount: 1,
      changedCount: 0,
    );
  }
}

void main() {
  setUpAll(() => RustLib.initMock(api: fixture.Api()));
  for (final queued in [false, true]) {
    test(queued ? '排在只读作业后的创建确认不采用新路线' : '等待材料校验的创建确认不采用新路线', () async {
      final evidence = Directory('../../.ubaa_local/agenda_sync_route').absolute
        ..createSync(recursive: true);
      final directory = evidence.createTempSync('materials_');
      addTearDown(() => directory.delete(recursive: true));
      final materials = SecureMaterialStore(
        coordinator: MaterialCoordinator(directory: directory),
        transport: MemoryMaterials(),
      );
      await materials.probe();
      final accounts = SecureLocalAccountStore(materials);
      await accounts.retain('fixture-route-confirmation', retainSession: true);
      final binding = await accounts.bindSnapshot((await accounts.capture())!);
      final client = RouteClient();
      final context = BridgeContext(client, configDirectory: directory.path)
        ..sharedAccount = binding;
      final service = AgendaService(BridgeAgendaBackend(context));
      addTearDown(service.dispose);
      await service.openAccount(binding.account.id);
      await service.sync(AgendaSyncAction.pull, fixture.now);
      await bridgeSetDefaultRoutePolicy(context, RoutePolicy.webvpn);
      await expectLater(
        service.sync(AgendaSyncAction.pull, fixture.now),
        throwsA(isA<Object>()),
      );
      // 实际状态卡仍从 report 提供创建入口；此刻打开和提交均处于 WebVPN。
      expect(service.syncState.running, isFalse);
      expect(service.syncState.report?.status, AgendaSyncStatus.needsCreation);
      expect(service.syncState.error, isNotNull);

      final held = Completer<void>();
      final release = Completer<void>();
      final materialOwner = materials.coordinate(() async {
        held.complete();
        await release.future;
      });
      await held.future;
      final starting = service.syncUpdates.firstWhere((state) => state.running);
      final previous = queued
          ? service.sync(AgendaSyncAction.pull, fixture.now)
          : null;
      if (queued) await starting;
      final job = service.prepareSync(
        AgendaSyncAction.createConfirmed,
        fixture.now,
      );
      final confirmed = expectLater(
        job(),
        throwsA(
          isA<AgendaException>().having(
            (e) => e.failure,
            '过期确认',
            AgendaFailure.superseded,
          ),
        ),
      );
      if (!queued) await starting;
      Future<BackendRouteSettings>? switching;
      try {
        expect(client.dispatched.map((call) => call.$2), [
          BridgeAgendaSyncAction.pull,
          BridgeAgendaSyncAction.pull,
        ]);
        client.routeMaterials = materials;
        switching = bridgeSetDefaultRoutePolicy(context, RoutePolicy.direct);
        await client.routeOwnsClient.future;
        expect(client.route, BridgeRoutePolicy.webVpn);
      } finally {
        release.complete();
        await materialOwner;
        await switching;
        await previous;
        await confirmed;
      }
      expect(
        client.dispatched.where(
          (call) => call.$2 == BridgeAgendaSyncAction.createConfirmed,
        ),
        isEmpty,
      );
      final fresh = await service.sync(
        AgendaSyncAction.createConfirmed,
        fixture.now,
      );
      expect(fresh.status, AgendaSyncStatus.needsCreation);
      expect(client.dispatched.last, (
        BridgeRoutePolicy.direct,
        BridgeAgendaSyncAction.createConfirmed,
      ));
    });
  }
}
