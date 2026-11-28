import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';

import '../support/bridge/recording_client.dart';
import '../support/controller/clock_accounts.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _ReadbackApi()));
  for (final (operation, feature, route, page, size, prepare, query) in [
    (
      BridgeWriteOperation.libbookReserve,
      FeatureId.libbook,
      BridgeConnectionMode.direct,
      1,
      20,
      _prepareLibbookReserve,
      null,
    ),
    (
      BridgeWriteOperation.libbookCancelBooking,
      FeatureId.libbook,
      BridgeConnectionMode.webVpn,
      3,
      12,
      _prepareLibbookCancel,
      null,
    ),
    (
      BridgeWriteOperation.cgyySubmitReservation,
      FeatureId.cgyy,
      BridgeConnectionMode.webVpn,
      0,
      20,
      _prepareCgyyReserve,
      null,
    ),
    (
      BridgeWriteOperation.cgyySubmitReservation,
      FeatureId.cgyy,
      BridgeConnectionMode.direct,
      2,
      15,
      _prepareCgyyReserve,
      const FeatureQuery(view: FeatureQueryView.cgyyOrders, page: 2, size: 15),
    ),
  ]) {
    for (final (label, unknown, readFails) in [
      ('提交成功', false, false),
      ('提交成功且回读失败', false, true),
      ('结果未知', true, false),
      ('结果未知且回读失败', true, true),
    ]) {
      test('${operation.name} 第 $page 页 $label，确认后仅回读原路线和指定页', () async {
        final cached =
            unknown && operation == BridgeWriteOperation.libbookCancelBooking;
        final client =
            _ReadbackClient(
                route: route,
                readFails: readFails,
                unknown: unknown,
              )
              ..commitResult = BridgeWriteCommitResult(
                operation: operation,
                success: true,
                message: '提交响应',
                outcomeUnknown: false,
                resolvedRoute: route,
                cgyyReceipt:
                    operation == BridgeWriteOperation.cgyySubmitReservation
                    ? const BridgeCgyyReservationReceipt(
                        orderId: 42,
                        venueSiteId: 7,
                        reservationDate: '2026-09-04',
                        orderStatus: 1,
                      )
                    : null,
              );
        final controller = AppController(
          backend: BridgeBackend(
            client,
            configDirectory: cached ? '/synthetic' : null,
          ),
          localAccountStore: cached ? ClockAccounts() : null,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.phase, AppPhase.home);
        if (cached) {
          await controller.recoverSession(refreshHomeAfter: false);
          expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
        }
        final intent = await prepare(controller);
        expect(
          intent.resolvedRoute,
          route == BridgeConnectionMode.direct
              ? ConnectionMode.direct
              : ConnectionMode.webvpn,
        );
        final writes = controller.writeCoordinator;
        writes.setIntent(
          query == null ? intent : intent.withReadbackQuery(query),
        );

        // 缓存提交会另行排队普通刷新。切后台只推迟这次刷新，保留写后固定路线回读。
        if (cached) controller.setAppForeground(false);
        final outcome = await writes.confirmForUi();

        final method = feature == FeatureId.libbook
            ? 'libbookBookingsOnRoute'
            : 'cgyyOrdersOnRoute';
        if (unknown) {
          expect(outcome?.result, isNull);
          expect(outcome?.error?.code, UbaaErrorCode.outcomeUnknown);
          expect(outcome?.message, allOf(contains('刷新后查看'), contains('勿重复提交')));
        } else {
          expect(outcome?.result?.success, isTrue);
          expect(outcome?.result?.outcomeUnknown, isFalse);
        }
        expect(await writes.confirmForUi(), isNull);
        expect(
          client.calls.where(
            (call) =>
                call.startsWith('commitWrite') ||
                call.startsWith('libbookBookings') ||
                call.startsWith('cgyyOrders'),
          ),
          [
            '${cached ? 'commitWriteCached' : 'commitWrite'}:intentId=${intent.intentId}',
            '$method:route=${route.name},page=$page,size=$size',
          ],
        );
        expect(
          controller.snapshots[feature]?.status,
          readFails
              ? FeatureLoadStatus.failure
              : feature == FeatureId.cgyy && page == 0
              ? FeatureLoadStatus.success
              : FeatureLoadStatus.empty,
        );
        if (feature == FeatureId.cgyy && !unknown) {
          expect(outcome?.cgyyReceiptVerified, !readFails && page == 0);
        }
      });
    }
  }
}

Future<WriteIntent> _prepareLibbookReserve(AppController controller) =>
    controller.prepareLibbookReserveWrite(
      const LibbookReserveAction(
        areaId: 'test-area',
        seatId: 'test-seat',
        day: '2026-09-04',
        segment: '1',
        startTime: '08:00',
        endTime: '10:00',
        eligibility: ActionEligibility.allowed,
      ),
    );

Future<WriteIntent> _prepareLibbookCancel(AppController controller) =>
    controller.prepareLibbookCancelWrite(
      const LibbookCancelAction(
        bookingId: 'test-booking',
        page: 3,
        limit: 12,
        eligibility: ActionEligibility.allowed,
      ),
    );

Future<WriteIntent> _prepareCgyyReserve(AppController controller) =>
    controller.prepareCgyySubmitWrite(
      const CgyySubmitInput(
        actions: [
          CgyyReserveAction(
            venueSiteId: 7,
            reservationDate: '2026-09-04',
            spaceId: 8,
            timeId: 9,
            venueSpaceGroupId: 10,
            timeOrdinal: 0,
            eligibility: ActionEligibility.allowed,
          ),
        ],
        phone: 'phone-placeholder',
        theme: '课程讨论',
        purposeType: 2,
        joinerNum: 3,
        activityContent: '公开活动摘要',
        joiners: '参与人占位',
        isPhilosophySocialSciences: false,
        isOffSchoolJoiner: false,
      ),
    );

class _ReadbackClient extends FixtureCharacterizationBridgeClient {
  _ReadbackClient({
    required this.route,
    required this.readFails,
    required this.unknown,
  });

  final BridgeConnectionMode route;
  final bool readFails, unknown;

  BridgeError get _unknownError => BridgeError(
    code: BridgeErrorCode.outcomeUnknown,
    kind: BridgeErrorKind.network,
    retryable: false,
    message: '合成发送后结果未知',
    resolvedRoute: route,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final result = super.noSuchMethod(invocation);
    if (result is! Future<BridgeWriteIntent>) return result;
    return result.then(
      (intent) => BridgeWriteIntent(
        intentId: intent.intentId,
        operation: intent.operation,
        targetSummary: intent.targetSummary,
        resolvedRoute: route,
        warnings: intent.warnings,
        expiresAt: intent.expiresAt,
        requestDigest: intent.requestDigest,
      ),
    );
  }

  @override
  Future<BridgeWriteCommitResult> commitWrite({
    required String intentId,
  }) async {
    calls.add('commitWrite:intentId=$intentId');
    if (unknown) throw _unknownError;
    return commitResult;
  }

  @override
  Future<BridgeCachedWriteCommit> commitWriteCached({
    required BridgeOfflineCache cache,
    required String intentId,
  }) async {
    expect(cache, isA<_ReadbackCache>());
    calls.add('commitWriteCached:intentId=$intentId');
    return BridgeCachedWriteCommit(error: _unknownError);
  }

  @override
  Future<BridgeRequiredSession> recoverRequiredSessionControlled({
    required BridgeRecoveryFeature feature,
    required BridgeRequiredRecoveryControl control,
  }) async => BridgeRequiredSession(
    route: route,
    profile: const BridgeUserProfile(username: 'fixture-user'),
  );

  @override
  Future<BridgeRoutedUserProfile> userInfo() async =>
      const BridgeRoutedUserProfile(
        data: BridgeUserProfile(username: 'fixture-user', name: '测试用户'),
        route: fixtureWebVpnRoute,
      );

  @override
  Future<BridgePinnedLibbookBookings> libbookBookingsOnRoute({
    required BridgeConnectionMode route,
    required int page,
    required int limit,
  }) async {
    calls.add(
      'libbookBookingsOnRoute:route=${route.name},page=$page,size=$limit',
    );
    if (readFails) throw _readError;
    return BridgePinnedLibbookBookings(
      data: BridgeLibBookBookingsPage(
        bookings: const [],
        page: page,
        limit: limit,
        total: 0,
      ),
      pinnedRoute: route,
    );
  }

  @override
  Future<BridgeCallerPinnedCgyyOrders> cgyyOrdersOnRoute({
    required BridgeConnectionMode route,
    required int page,
    required int size,
  }) async {
    calls.add('cgyyOrdersOnRoute:route=${route.name},page=$page,size=$size');
    if (readFails) throw _readError;
    return BridgeCallerPinnedCgyyOrders(
      data: BridgeCgyyOrdersPage(
        content: page == 0
            ? const [
                BridgeCgyyOrder(
                  id: 42,
                  orderStatus: 1,
                  checkStatus: 2,
                  cancelEligibility: BridgeActionEligibility.denied,
                ),
              ]
            : const [],
        totalElements: 1,
        totalPages: 1,
        size: size,
        number: page,
      ),
      pinnedRoute: route,
    );
  }
}

const _readError = BridgeError(
  code: BridgeErrorCode.upstreamUnavailable,
  kind: BridgeErrorKind.upstream,
  retryable: true,
  message: '只读请求失败',
);

class _ReadbackApi implements RustLibApi {
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => _ReadbackCache();

  @override
  BridgeRequiredRecoveryControl
  crateApiRecoveryControlBridgeRequiredRecoveryControlNew({
    required int timeoutMillis,
  }) => _RecoveryControl();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveryControl implements BridgeRequiredRecoveryControl {
  @override
  void cancel() {}
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadbackCache implements BridgeOfflineCache {
  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  Future<void> close() async {}
  @override
  void dispose() {}
  @override
  Future<List<BridgeWriteReadbackHint>> writeReadbackHints() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
