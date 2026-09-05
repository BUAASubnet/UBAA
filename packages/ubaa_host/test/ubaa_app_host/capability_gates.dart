part of '../ubaa_app_host_test.dart';

void _registerCapabilityGateTests() {
  testWidgets('共享宿主在照片选择器不可用时整组关闭阳光打卡能力', (tester) async {
    final backend = _RecordingBackend()..signedIn = true;
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        photoPicker: const UnavailablePhotoPicker(),
        permissionGateway: MemoryPermissionGateway(),
        initialTab: 2,
      ),
    );
    await tester.pumpAndSettle();

    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.onPrepareYgdkSubmitWrite, isNull);
    expect(shell.onRefreshYgdkAfterWrite, isNull);
    expect(shell.onPickYgdkPhoto, isNull);
  });

  testWidgets('共享宿主在权限网关缺失时整组关闭阳光打卡能力', (tester) async {
    final backend = _RecordingBackend()..signedIn = true;
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        photoPicker: MemoryPhotoPicker(photo: _safeHostPhoto),
        initialTab: 2,
      ),
    );
    await tester.pumpAndSettle();

    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.onPrepareYgdkSubmitWrite, isNull);
    expect(shell.onRefreshYgdkAfterWrite, isNull);
    expect(shell.onPickYgdkPhoto, isNull);
  });

  testWidgets('共享宿主在 backend 缺少写入或回读任一接口时整组关闭', (tester) async {
    for (final backend in <UbaaBackend>[
      _HostYgdkWriteOnlyBackend(),
      _HostYgdkReadbackOnlyBackend(),
    ]) {
      await tester.pumpWidget(
        UbaaAppHost(
          key: UniqueKey(),
          backend: backend,
          photoPicker: MemoryPhotoPicker(photo: _safeHostPhoto),
          permissionGateway: MemoryPermissionGateway(),
          initialTab: 2,
        ),
      );
      await tester.pumpAndSettle();

      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(shell.onPrepareYgdkSubmitWrite, isNull);
      expect(shell.onPickYgdkPhoto, isNull);
      expect(shell.onRefreshYgdkAfterWrite, isNull);
    }
  });

  testWidgets('共享宿主在评教 backend 缺少写入或回读任一接口时成对关闭', (tester) async {
    for (final backend in <UbaaBackend>[
      _HostEvaluationWriteOnlyBackend(),
      _HostEvaluationReadbackOnlyBackend(),
    ]) {
      await tester.pumpWidget(
        UbaaAppHost(key: UniqueKey(), backend: backend, initialTab: 2),
      );
      await tester.pumpAndSettle();

      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(shell.onPrepareEvaluationWrite, isNull);
      expect(shell.onRefreshEvaluationAfterWrite, isNull);
    }
  });

  testWidgets('共享宿主把提交异常隔离为 domain UiError', (tester) async {
    final backend = _RecordingBackend()..signedIn = true;
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));

    backend.commitFailure = const BackendException(UbaaErrorCode.networkError);
    await expectLater(
      shell.onCommitWrite!('intent-network-error'),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.networkError,
        ),
      ),
    );

    backend.commitFailure = StateError('/private/token=secret');
    await expectLater(
      shell.onCommitWrite!('intent-internal-error'),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.internalError,
        ),
      ),
    );
  });
}
