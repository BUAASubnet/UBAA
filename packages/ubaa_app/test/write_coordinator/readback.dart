part of '../write_coordinator_test.dart';

void _registerReadbackTests() {
  test('场馆预约先刷新订单再匹配收据且保留原结果', () async {
    final calls = <String>[];
    final result = _result(
      operation: WriteOperation.cgyySubmitReservation,
      receipt: const CgyyReservationReceipt(orderId: 42),
    );
    final coordinator = WriteCoordinator(
      commit: (_) async {
        calls.add('commit');
        return result;
      },
      receiptVerifier: WriteReceiptVerifier(
        refreshAfterWrite: (operation, _) async {
          expect(operation, WriteOperation.cgyySubmitReservation);
          calls.add('refresh');
        },
        verifyCgyyReceipt: (receipt) async {
          expect(receipt.orderId, 42);
          calls.add('receipt');
          return true;
        },
      ),
      now: () => _now,
    );
    coordinator.setIntent(
      _intent(operation: WriteOperation.cgyySubmitReservation),
    );
    final outcome = await coordinator.confirmForUi();
    expect(calls, <String>['commit', 'refresh', 'receipt']);
    expect(outcome?.result, same(result));
    expect(outcome?.cgyyReceiptVerified, isTrue);
    expect(outcome?.message, contains('订单编号 42，订单列表已核对'));
    coordinator.dispose();
  });

  test('场馆取消未知结果只在原路线双回读且不升级为成功', () async {
    var genericReads = 0;
    final coordinator = WriteCoordinator(
      commit: (_) async =>
          throw const BackendException(UbaaErrorCode.outcomeUnknown),
      receiptVerifier: WriteReceiptVerifier(
        refreshAfterWrite: (_, _) async {
          genericReads++;
        },
        verifyCgyyCancellation:
            ({required orderId, required expectedRoute}) async {
              expect(orderId, 42);
              expect(expectedRoute, ConnectionMode.webvpn);
              return true;
            },
      ),
      now: () => _now,
    );
    coordinator.setIntent(
      _intent(
        operation: WriteOperation.cgyyCancelOrder,
        readbackQuery: const FeatureQuery(
          view: FeatureQueryView.cgyyOrderDetail,
          orderId: 42,
        ),
      ),
    );
    final outcome = await coordinator.confirmForUi();
    expect(outcome?.error?.code, UbaaErrorCode.outcomeUnknown);
    expect(outcome?.cgyyCancellationVerified, isTrue);
    expect(outcome?.message, '提交响应不确定，但场馆订单取消状态已核对，请勿重复提交。');
    expect(genericReads, 0);
    coordinator.dispose();
  });

  test('阳光打卡回读失败只记录尝试且不改变未知结果', () async {
    final result = _result(operation: WriteOperation.ygdkSubmit, unknown: true);
    final coordinator = WriteCoordinator(
      commit: (_) async => result,
      receiptVerifier: WriteReceiptVerifier(
        refreshYgdkAfterWrite: ({required expectedRoute}) async {
          expect(expectedRoute, ConnectionMode.webvpn);
          throw StateError('读取失败');
        },
      ),
      now: () => _now,
    );
    coordinator.setIntent(_intent(operation: WriteOperation.ygdkSubmit));
    final outcome = await coordinator.confirmForUi();
    expect(outcome?.result, same(result));
    expect(outcome?.ygdkReadbackAttempted, isTrue);
    expect(outcome?.message, '提交结果不确定；已尝试按原路线刷新概览与记录，请勿重复提交。');
    coordinator.dispose();
  });

  test('评教批量确定失败和提交异常仍各执行一次原路线回读', () async {
    for (final throwsError in <bool>[false, true]) {
      var reads = 0;
      final coordinator = WriteCoordinator(
        commit: (_) async {
          if (throwsError) throw StateError('内部错误');
          return _result(
            operation: WriteOperation.evaluationSubmitCourses,
            success: false,
            evaluationResult: const EvaluationBatchResult(
              items: <EvaluationCourseResult>[],
              success: false,
              outcomeUnknown: false,
            ),
          );
        },
        receiptVerifier: WriteReceiptVerifier(
          refreshEvaluationAfterWrite: ({required expectedRoute}) async {
            expect(expectedRoute, ConnectionMode.webvpn);
            reads++;
          },
        ),
        now: () => _now,
      );
      coordinator.setIntent(
        _intent(operation: WriteOperation.evaluationSubmitCourses),
      );
      final outcome = await coordinator.confirmForUi();
      expect(reads, 1);
      expect(outcome?.operation, WriteOperation.evaluationSubmitCourses);
      expect(outcome?.result?.success ?? false, isFalse);
      coordinator.dispose();
    }
  });

  test('提交结果操作错配以原意图的未知结果回读', () async {
    final coordinator = WriteCoordinator(
      commit: (_) async => _result(operation: WriteOperation.signinPerform),
      receiptVerifier: WriteReceiptVerifier(
        refreshAfterWrite: (operation, _) async {
          expect(operation, WriteOperation.bykcSelectCourse);
        },
      ),
      now: () => _now,
    );
    coordinator.setIntent(_intent());
    final outcome = await coordinator.confirmForUi();
    expect(outcome?.result, isNull);
    expect(outcome?.error?.code, UbaaErrorCode.outcomeUnknown);
    expect(outcome?.message, '提交结果不确定，请先刷新相关状态，不要重复提交。');
    coordinator.dispose();
  });

  test('普通写入刷新失败不改变确定提交结果', () async {
    final result = _result();
    final coordinator = WriteCoordinator(
      commit: (_) async => result,
      receiptVerifier: WriteReceiptVerifier(
        refreshAfterWrite: (_, _) async => throw StateError('读取失败'),
      ),
      now: () => _now,
    );
    coordinator.setIntent(_intent());
    final outcome = await coordinator.confirmForUi();
    expect(outcome?.result, same(result));
    expect(outcome?.error, isNull);
    coordinator.dispose();
  });
}
