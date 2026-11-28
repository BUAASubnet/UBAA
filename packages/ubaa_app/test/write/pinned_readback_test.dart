import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../support/bridge/recording_client.dart';

void main() {
  for (final (operation, feature, page, size, prepare, query) in [
    (
      BridgeWriteOperation.libbookReserve,
      FeatureId.libbook,
      1,
      20,
      _prepareLibbookReserve,
      null,
    ),
    (
      BridgeWriteOperation.libbookCancelBooking,
      FeatureId.libbook,
      3,
      12,
      _prepareLibbookCancel,
      null,
    ),
    (
      BridgeWriteOperation.cgyySubmitReservation,
      FeatureId.cgyy,
      0,
      20,
      _prepareCgyyReserve,
      null,
    ),
    (
      BridgeWriteOperation.cgyySubmitReservation,
      FeatureId.cgyy,
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
        final client = _ReadbackClient(readFails: readFails)
          ..commitResult = BridgeWriteCommitResult(
            operation: operation,
            success: !unknown,
            message: '提交响应',
            outcomeUnknown: unknown,
            resolvedRoute: BridgeConnectionMode.webVpn,
            cgyyReceipt: operation == BridgeWriteOperation.cgyySubmitReservation
                ? const BridgeCgyyReservationReceipt(
                    orderId: 42,
                    venueSiteId: 7,
                    reservationDate: '2026-09-04',
                    orderStatus: 1,
                  )
                : null,
          );
        final controller = AppController(backend: BridgeBackend(client));
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.phase, AppPhase.home);
        final intent = await prepare(controller);
        final writes = controller.writeCoordinator;
        writes.setIntent(
          query == null ? intent : intent.withReadbackQuery(query),
        );

        final outcome = await writes.confirmForUi();

        final method = feature == FeatureId.libbook
            ? 'libbookBookingsOnRoute'
            : 'cgyyOrdersOnRoute';
        expect(outcome?.result?.outcomeUnknown, unknown);
        if (unknown) {
          expect(outcome?.message, allOf(contains('刷新'), contains('勿重复提交')));
        }
        expect(await writes.confirmForUi(), isNull);
        expect(
          client.calls.where(
            (call) =>
                call.startsWith('commitWrite:') ||
                call.startsWith('libbookBookings') ||
                call.startsWith('cgyyOrders'),
          ),
          [
            'commitWrite:intentId=${intent.intentId}',
            '$method:route=webVpn,page=$page,size=$size',
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
  _ReadbackClient({required this.readFails});

  final bool readFails;

  @override
  Future<BridgeRoutedUserProfile> userInfo() async =>
      const BridgeRoutedUserProfile(
        data: BridgeUserProfile(username: 'test-user', name: '测试用户'),
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
