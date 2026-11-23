import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/controller/app_controller.dart';
import 'package:ubaa_app/src/controller/write/library_readback.dart';
import 'package:ubaa_app/src/write/receipt_verifier.dart';
import 'package:ubaa_app/src/write/coordinator.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

import '../support/bridge/recording_client.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class _RenewalRejectionClient extends FixtureCharacterizationBridgeClient {
  _RenewalRejectionClient(this.error);

  final BridgeError error;

  @override
  Future<BridgeWriteCommitResult> commitWrite({
    required String intentId,
  }) async {
    calls.add('commitWrite:intentId=$intentId');
    throw error;
  }
}

class _ReadbackBackend
    implements UbaaBackend, LibraryLoanReadbackBackend, LibraryLoansBackend {
  _ReadbackBackend(this.result);

  final LibraryLoanRouteRead result;
  final List<ConnectionMode> routes = <ConnectionMode>[];
  int normalReads = 0;
  Object? failure;
  Completer<void>? gate;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      FeatureResult.success(summary: feature.title);

  @override
  Future<List<LibraryLoan>> readLibraryLoans() async {
    normalReads++;
    return result.loans;
  }

  @override
  Future<LibraryLoanRouteRead> readLibraryLoansOnRoute({
    required ConnectionMode route,
  }) async {
    routes.add(route);
    if (gate case final gate?) await gate.future;
    if (failure case final error?) throw error;
    return result;
  }
}

WriteIntent _intent(ConnectionMode route, {String? dueDate = '2026-12-01'}) =>
    WriteIntent(
      intentId: 'intent-library',
      operation: WriteOperation.libraryLoanRenew,
      targetSummary: '《合成书目》',
      resolvedRoute: route,
      warnings: const <String>[],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
      libraryLoanRenewTarget: LibraryLoanRenewTarget(
        loanId: 'loan-1',
        dueDate: dueDate,
        renewTimes: 1,
      ),
    );

LibraryLoan _loan({String dueDate = '2027-01-05', int renewTimes = 2}) =>
    LibraryLoan(
      id: 'loan-1',
      title: '合成书目',
      dueDate: dueDate,
      renewTimes: renewTimes,
    );

void main() {
  test('同一会话重建后端保留待核对借阅，新会话不继承', () async {
    final backend = _ReadbackBackend(
      const LibraryLoanRouteRead(
        loans: [],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    controller.internalWriteCoordinator.dispose();
    final previous = WriteCoordinator(
      commit: (_) async =>
          throw const BackendException(UbaaErrorCode.outcomeUnknown),
      discard: (_) async {},
      receiptVerifier: WriteReceiptVerifier(),
    );
    controller.internalWriteCoordinator = previous;
    previous.setIntent(_intent(ConnectionMode.direct));
    await previous.confirmForUi();
    expect(previous.pendingLibraryLoanIds, {'loan-1'});
    controller.internalReplaceWriteCoordinator(backend, sameSession: true);
    expect(controller.writeCoordinator.pendingLibraryLoanIds, {'loan-1'});
    controller.internalReplaceWriteCoordinator(backend);
    expect(controller.writeCoordinator.pendingLibraryLoanIds, isEmpty);
  });

  test('未知续借在只读核对前拒绝再次签发同书意图', () async {
    var sends = 0;
    final closed = <String>[];
    LibraryLoanRenewReadback? nextRead;
    final writes = WriteCoordinator(
      commit: (_) async {
        sends++;
        throw const BackendException(
          UbaaErrorCode.outcomeUnknown,
          readbackHintId: 'this-hint',
        );
      },
      discard: (_) async {},
      dismissVerifiedLibraryHint: (id) async => closed.add(id),
      receiptVerifier: WriteReceiptVerifier(
        verifyLibraryLoanRenew: (_) async => nextRead,
      ),
    );
    addTearDown(writes.dispose);
    final intent = _intent(ConnectionMode.direct);
    writes.setIntent(intent);
    await writes.confirmForUi();
    await expectLater(
      writes.prepare(() async => intent),
      throwsA(isA<BackendException>()),
    );
    writes.setIntent(intent);
    expect(writes.intent, isNull);
    expect(
      () => writes.ensureLibraryLoanCanPrepare('loan-1'),
      throwsA(isA<BackendException>()),
    );
    writes.ensureLibraryLoanCanPrepare('loan-2');
    await writes.recheckLibraryLoan('loan-1');
    expect(writes.pendingLibraryLoanIds, {'loan-1'});
    expect(closed, isEmpty);
    nextRead = const LibraryLoanRenewReadback(
      loanId: 'loan-1',
      loans: [],
      route: ConnectionMode.direct,
      status: LibraryRenewStatus.unchanged,
    );
    await writes.recheckLibraryLoan('loan-1');
    expect(writes.pendingLibraryLoanIds, isEmpty);
    expect(closed, ['this-hint']);
    expect(await writes.prepare(() async => intent), intent);
    expect(sends, 1);
  });
  test('网络就绪前更换会话时不读取旧后端', () async {
    final previous = _ReadbackBackend(
      LibraryLoanRouteRead(
        loans: [_loan()],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    final replacement = _ReadbackBackend(
      const LibraryLoanRouteRead(
        loans: [],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    final controller = AppController(backend: previous);
    addTearDown(controller.dispose);
    final ready = Completer<void>();
    controller.internalNetworkReady = ready;
    controller.internalNetworkChecking = true;

    final read = expectLater(
      controller.readLibraryLoans(),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    // 网络恢复可以重建客户端，并在替换完成后才放行等待中的服务读。
    final session = controller.internalSessionLifecycle;
    session.beginRebuild();
    session.invalidate();
    session.replaceBackend(replacement);
    session.endRebuild();
    controller.internalNetworkChecking = false;
    ready.complete();

    await read;
    expect(previous.normalReads, 0);
    expect(replacement.normalReads, 0);
  });

  test('续借核对只读取意图绑定路线并识别同一记录已更新', () async {
    final backend = _ReadbackBackend(
      LibraryLoanRouteRead(
        loans: [_loan()],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    final controller = AppController(backend: backend);

    final result = await controllerVerifyLibraryLoanRenew(
      controller,
      _intent(ConnectionMode.direct),
    );

    expect(backend.routes, [ConnectionMode.direct]);
    expect(result?.route, ConnectionMode.direct);
    expect(result?.loanId, 'loan-1');
    expect(result?.verified, isTrue);
    controller.dispose();
  });

  test('意图为 WebVPN 时核对固定 WebVPN 而不走普通读取', () async {
    final backend = _ReadbackBackend(
      LibraryLoanRouteRead(
        loans: [_loan()],
        resolvedRoute: ConnectionMode.webvpn,
      ),
    );
    final webvpnOnly = AppController(backend: backend);

    final result = await controllerVerifyLibraryLoanRenew(
      webvpnOnly,
      _intent(ConnectionMode.webvpn),
    );

    expect(backend.routes, [ConnectionMode.webvpn]);
    expect(backend.normalReads, 0);
    expect(result?.route, ConnectionMode.webvpn);
    expect(result?.verified, isTrue);
  });

  test('预检应还日期未知且次数未增加时不能核对为成功', () async {
    final backend = _ReadbackBackend(
      LibraryLoanRouteRead(
        loans: [_loan(renewTimes: 1)],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    final controller = AppController(backend: backend);
    final result = await controllerVerifyLibraryLoanRenew(
      controller,
      _intent(ConnectionMode.direct, dueDate: null),
    );
    expect(result?.verified, isFalse);
    controller.dispose();
  });

  test('核对只接受日期延后或次数增加', () async {
    for (final (date, count, verified) in [
      ('2026-12-01 12:30:45', 1, false),
      ('2026-11-30', 1, false),
      ('2027-02-29', 1, false),
      ('2026-12-02 24:00:00', 1, false),
      ('日期未知', 1, false),
      ('2026-12-02 00:00:00', 1, true),
      ('日期未知', 2, true),
    ]) {
      final backend = _ReadbackBackend(
        LibraryLoanRouteRead(
          loans: [_loan(dueDate: date, renewTimes: count)],
          resolvedRoute: ConnectionMode.direct,
        ),
      );
      final controller = AppController(backend: backend);
      final read = await controllerVerifyLibraryLoanRenew(
        controller,
        _intent(ConnectionMode.direct),
      );
      controller.dispose();
      expect(read?.verified, verified, reason: '$date / $count');
      expect(
        read?.status == LibraryRenewStatus.unchanged,
        date == '2026-12-01 12:30:45',
      );
    }
  });

  test('记录未变化或回读路线不一致时保留未核对', () async {
    final unchanged = _ReadbackBackend(
      LibraryLoanRouteRead(
        loans: [_loan(dueDate: '2026-12-01', renewTimes: 1)],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    final first = AppController(backend: unchanged);
    final result = await controllerVerifyLibraryLoanRenew(
      first,
      _intent(ConnectionMode.direct),
    );
    expect(result?.verified, isFalse);
    expect(result?.loans.single.dueDate, '2026-12-01');
    first.dispose();

    final changedRoute = _ReadbackBackend(
      LibraryLoanRouteRead(
        loans: [_loan()],
        resolvedRoute: ConnectionMode.webvpn,
      ),
    );
    final second = AppController(backend: changedRoute);
    final mismatch = await controllerVerifyLibraryLoanRenew(
      second,
      _intent(ConnectionMode.direct),
    );
    expect(changedRoute.routes, [ConnectionMode.direct]);
    expect(mismatch, isNull);
    second.dispose();
  });

  test('读取期间账号或会话作用域失效时丢弃迟到核对', () async {
    final backend = _ReadbackBackend(
      LibraryLoanRouteRead(
        loans: [_loan()],
        resolvedRoute: ConnectionMode.direct,
      ),
    )..gate = Completer<void>();
    final controller = AppController(backend: backend);

    final pending = controllerVerifyLibraryLoanRenew(
      controller,
      _intent(ConnectionMode.direct),
    );
    await Future<void>.delayed(Duration.zero);
    expect(backend.routes, [ConnectionMode.direct]);
    controller.dispose();
    backend.gate!.complete();

    expect(await pending, isNull);
  });

  test('回读失败返回空核对且不触发新的写请求', () async {
    final backend = _ReadbackBackend(
      const LibraryLoanRouteRead(
        loans: <LibraryLoan>[],
        resolvedRoute: ConnectionMode.direct,
      ),
    )..failure = StateError('synthetic read failure');
    final controller = AppController(backend: backend);

    final result = await controllerVerifyLibraryLoanRenew(
      controller,
      _intent(ConnectionMode.direct),
    );

    expect(result, isNull);
    expect(backend.routes, [ConnectionMode.direct]);
    controller.dispose();
  });

  _verifierTests();
}

void _verifierTests() {
  test('统一写入生命周期在成功和未知结果后执行续借核对', () async {
    final readback = LibraryLoanRenewReadback(
      loanId: 'loan-1',
      loans: [_loan()],
      route: ConnectionMode.direct,
      status: LibraryRenewStatus.applied,
    );
    var calls = 0;
    final verifier = WriteReceiptVerifier(
      verifyLibraryLoanRenew: (intent) async {
        calls++;
        expect(intent.resolvedRoute, ConnectionMode.direct);
        return readback;
      },
    );
    final success = await verifier.complete(
      _intent(ConnectionMode.direct),
      result: const WriteCommitResult(
        operation: WriteOperation.libraryLoanRenew,
        success: true,
        message: '续借成功',
        outcomeUnknown: false,
        resolvedRoute: ConnectionMode.direct,
      ),
      isCurrent: () => true,
    );
    expect(calls, 1);
    expect(success.libraryLoanRenewReadback, same(readback));

    final unknown = await verifier.complete(
      _intent(ConnectionMode.direct),
      result: const WriteCommitResult(
        operation: WriteOperation.libraryLoanRenew,
        success: false,
        message: '结果未确认',
        outcomeUnknown: true,
        resolvedRoute: ConnectionMode.direct,
      ),
      isCurrent: () => true,
    );
    expect(calls, 2);
    expect(unknown.libraryLoanRenewReadback, same(readback));
  });

  test('续借原因只进入本次提交反馈，诊断仍使用通用提示', () async {
    const reason = '尚未进入续借窗口，请稍后再试';
    final client = _RenewalRejectionClient(
      const BridgeError(
        code: BridgeErrorCode.businessRejected,
        kind: BridgeErrorKind.upstream,
        retryable: false,
        message: reason,
        diagnosticJson:
            '{"source":"crates/ubaa_core/src/features/campus/library_loans.rs:1",'
            '"stage":"response","reason":"library_renew_rejected_with_message"}',
      ),
    );
    final backend = BridgeBackend(client);
    UiError? observed;
    final writes = WriteCoordinator(
      commit: backend.commitWrite,
      observeResult: (_, {required error, required route}) => observed = error,
    );
    addTearDown(writes.dispose);
    writes.setIntent(_intent(ConnectionMode.direct));

    final outcome = await writes.confirmForUi();

    expect(outcome?.message, reason);
    expect(outcome?.error?.code, UbaaErrorCode.businessRejected);
    expect(observed?.message, isNot(contains(reason)));
    expect(observed?.diagnostic?.toJson().toString(), isNot(contains(reason)));
    expect(client.calls, ['commitWrite:intentId=intent-library']);
  });

  test('确定业务拒绝不触发续借核对或写重试', () async {
    var calls = 0;
    final verifier = WriteReceiptVerifier(
      verifyLibraryLoanRenew: (intent) async {
        calls++;
        return null;
      },
    );
    final outcome = await verifier.complete(
      _intent(ConnectionMode.direct),
      error: const UiError(
        code: UbaaErrorCode.businessRejected,
        title: '续借未接受',
        message: '学校未接受本次续借',
      ),
      isCurrent: () => true,
    );
    expect(calls, 0);
    expect(outcome.libraryLoanRenewReadback, isNull);
  });
}
