import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/host/fakes.dart'
    show
        FixtureHostEvaluationReadbackOnlyBackend,
        FixtureHostEvaluationWriteOnlyBackend,
        FixtureHostYgdkReadbackOnlyBackend,
        FixtureHostYgdkWriteOnlyBackend,
        fixtureSafeHostPhoto;
import '../support/host/recording_backend.dart' show FixtureRecordingBackend;

void _registerCapabilityGateTests() {
  testWidgets('共享宿主在照片选择器不可用时整组关闭阳光打卡能力', (tester) async {
    final backend = FixtureRecordingBackend()..signedIn = true;
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
    expect(shell.onCaptureYgdkPhoto, isNull);
  });

  testWidgets('共享宿主在权限网关缺失时整组关闭阳光打卡能力', (tester) async {
    final backend = FixtureRecordingBackend()..signedIn = true;
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        photoPicker: MemoryPhotoPicker(photo: fixtureSafeHostPhoto),
        initialTab: 2,
      ),
    );
    await tester.pumpAndSettle();

    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.onPrepareYgdkSubmitWrite, isNull);
    expect(shell.onRefreshYgdkAfterWrite, isNull);
    expect(shell.onPickYgdkPhoto, isNull);
    expect(shell.onCaptureYgdkPhoto, isNull);
  });

  testWidgets('共享宿主在 backend 缺少写入或回读任一接口时整组关闭', (tester) async {
    for (final backend in <UbaaBackend>[
      FixtureHostYgdkWriteOnlyBackend(),
      FixtureHostYgdkReadbackOnlyBackend(),
    ]) {
      await tester.pumpWidget(
        UbaaAppHost(
          key: UniqueKey(),
          backend: backend,
          photoPicker: MemoryPhotoPicker(photo: fixtureSafeHostPhoto),
          permissionGateway: MemoryPermissionGateway(),
          initialTab: 2,
        ),
      );
      await tester.pumpAndSettle();

      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(shell.onPrepareYgdkSubmitWrite, isNull);
      expect(shell.onPickYgdkPhoto, isNull);
      expect(shell.onCaptureYgdkPhoto, isNull);
      expect(shell.onRefreshYgdkAfterWrite, isNull);
    }
  });

  testWidgets('共享宿主在评教 backend 缺少写入或回读任一接口时成对关闭', (tester) async {
    for (final backend in <UbaaBackend>[
      FixtureHostEvaluationWriteOnlyBackend(),
      FixtureHostEvaluationReadbackOnlyBackend(),
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
    final backend = FixtureRecordingBackend()..signedIn = true;
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

void main() {
  _registerCapabilityGateTests();
}
