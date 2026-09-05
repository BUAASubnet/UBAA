part of '../ubaa_app_host_test.dart';

void _registerWriteCoordinationTests() {
  testWidgets('共享宿主通过同一协调器发布确认状态并消费一次', (tester) async {
    final backend = _RecordingBackend()..signedIn = true;
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    var shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.writeState.phase, WritePhase.idle);

    final intent = await shell.onRunWritePrepare!(
      () async => WriteIntent(
        intentId: 'coordinated-host-intent',
        operation: WriteOperation.cgyySubmitReservation,
        targetSummary: '脱敏宿主确认目标',
        resolvedRoute: ConnectionMode.webvpn,
        warnings: const <String>[],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'digest',
      ),
      expectedOperation: WriteOperation.cgyySubmitReservation,
    );
    await tester.pumpAndSettle();
    shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(identical(shell.writeState.intent, intent), isTrue);
    expect(shell.writeState.phase, WritePhase.ready);
    expect(find.text('脱敏宿主确认目标'), findsOneWidget);

    final outcome = await shell.onConfirmWrite!();
    expect(outcome?.result, _RecordingBackend.commitResult);
    expect(backend.committedIntentId, 'coordinated-host-intent');
    expect(await shell.onConfirmWrite!(), isNull);
    await tester.pumpAndSettle();
    shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.writeState.phase, WritePhase.idle);
    expect(shell.writeState.intent, isNull);
  });

  testWidgets('位置等待期间注销后不再调用博雅业务准备', (tester) async {
    final backend = _RecordingBackend()..signedIn = true;
    final location = _DeferredHostLocation();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        locationProvider: location,
        permissionGateway: MemoryPermissionGateway(
          initial: <PlatformPermission, PlatformPermissionStatus>{
            PlatformPermission.foregroundLocation:
                PlatformPermissionStatus.granted,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    final preparing = shell.onRunWritePrepare!(
      () => shell.onPrepareBykcSignWrite!(
        const BykcSignAction(
          courseId: 41003,
          kind: BykcSignKind.signIn,
          eligibility: ActionEligibility.allowed,
          requiresCoordinates: true,
        ),
      ),
      expectedOperation: WriteOperation.bykcSignCourse,
    );
    await tester.pump();
    expect(location.started, isTrue);
    await shell.onLogout();
    location.pending.complete(PlatformLocation(lat: 39.9, lng: 116.3));
    expect(await preparing, isNull);
    await tester.pumpAndSettle();
    expect(backend.bykcSign, isNull);
    expect(backend.committedIntentId, isNull);
    expect(find.byType(UbaaLoginView), findsOneWidget);
  });

  testWidgets('照片等待期间注销后继续表单不再调用阳光业务准备', (tester) async {
    final backend = _PhotoLogoutBackend();
    final picker = _DeferredHostPhotoPicker();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        photoPicker: picker,
        permissionGateway: MemoryPermissionGateway(
          initial: <PlatformPermission, PlatformPermissionStatus>{
            PlatformPermission.photos: PlatformPermissionStatus.granted,
          },
        ),
        initialTab: 2,
      ),
    );
    await tester.pumpAndSettle();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    await tester.tap(find.text('阳光打卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备阳光打卡'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '2026-09-05 08:00');
    await tester.enterText(fields.at(1), '2026-09-05 09:00');
    await tester.tap(find.text('选择照片'));
    await tester.pump();
    expect(picker.started, isTrue);

    await shell.onLogout();
    await tester.pumpAndSettle();
    expect(backend.logoutCalls, 1);
    expect(find.byType(UbaaMainShell), findsNothing);
    picker.pending.complete(_safeHostPhoto);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();

    expect(backend.prepareCalls, 0);
    expect(backend.commitCalls, 0);
    expect(find.byType(WriteConfirmationView), findsNothing);
    expect(find.byType(UbaaLoginView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DeferredHostLocation implements PlatformLocationProvider {
  final pending = Completer<PlatformLocation?>();
  bool started = false;

  @override
  bool get isAvailable => true;

  @override
  Future<PlatformLocation?> currentLocation() {
    started = true;
    return pending.future;
  }
}

class _DeferredHostPhotoPicker implements PlatformPhotoPicker {
  final pending = Completer<YgdkPhotoInput?>();
  bool started = false;

  @override
  bool get isAvailable => true;

  @override
  Future<YgdkPhotoInput?> pickPhoto() {
    started = true;
    return pending.future;
  }
}

final class _PhotoLogoutBackend extends _HostReadOnlyBackend
    implements YgdkWriteBackend, YgdkSubmissionReadbackBackend {
  int prepareCalls = 0;
  int commitCalls = 0;
  int logoutCalls = 0;

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature == FeatureId.ygdk
      ? const FeatureResult.success(
          summary: '已加载',
          details: <FeatureDetail>[
            FeatureDetail(
              title: '跑步项目',
              actions: <FeatureAction>[
                YgdkSubmitAction(
                  classifyId: 31,
                  itemId: 7,
                  eligibility: ActionEligibility.allowed,
                ),
              ],
            ),
          ],
        )
      : const FeatureResult.empty();

  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async {
    prepareCalls++;
    return _hostYgdkIntent;
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    throw StateError('不应提交');
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {}

  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) async => const FeatureResult.empty();

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) async => const FeatureResult.empty();
}
