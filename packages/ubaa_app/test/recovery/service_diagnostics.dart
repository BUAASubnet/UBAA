part of 'service_test.dart';

Map<String, dynamic> _event(AppController controller, UiError error) {
  expect(error.issueId, isNotNull);
  final report =
      jsonDecode(controller.exportDiagnostics(issueId: error.issueId))
          as Map<String, dynamic>;
  return (report['events'] as List).single as Map<String, dynamic>;
}

void _registerServiceDiagnosticsTests() {
  test('云打印读取和部分失败返回各自可导出的事件，批次只计一次', () async {
    final telemetry = MockTelemetryClient();
    final backend = _Backend();
    final controller = await start(backend, telemetry: telemetry);
    final service = controller.cloudPrintService!;
    await service.documents(scans: true);
    await expectLater(
      service.documents(scans: false),
      throwsA(
        isA<UiError>()
            .having(
              (error) => _event(controller, error)['feature'],
              '读取功能',
              'cloud_print',
            )
            .having(
              (error) => _event(controller, error)['latency_ms'],
              '失败耗时',
              isA<int>(),
            ),
      ),
    );
    final results = await service.delete([
      '成功',
      '私有文件名',
      '私有文件路径',
    ], scans: false);
    expect(results.first, isNull);
    expect(_event(controller, results[1]!)['file_index'], 2);
    expect(_event(controller, results[2]!)['file_index'], 3);
    expect(controller.exportDiagnostics(), isNot(contains('私有文件')));
    final events = telemetry.records
        .where((entry) => entry.properties['feature'] == 'cloud_print')
        .map((entry) => entry.name);
    expect(events, [
      'feature_loaded',
      'feature_loaded',
      'feature_failed',
      'write_completed',
      'write_failed',
    ]);
    expect(
      telemetry.records
          .where(
            (r) =>
                r.name == 'feature_loaded' &&
                r.properties['feature'] == 'cloud_print',
          )
          .map((r) => r.properties['result']),
      ['success', 'failure'],
    );
    final count = telemetry.records.singleWhere(
      (r) => r.name == 'write_completed',
    );
    expect(count.properties['result'], 'failure');
  });

  test('云打印整体写入异常返回单个报告并按批次记录', () async {
    final telemetry = MockTelemetryClient();
    final controller = await start(_Backend(), telemetry: telemetry);
    await expectLater(
      controller.cloudPrintService!.upload(
        [const PrintSource(path: '/私有文件路径', name: '私有文件名')],
        const PrintOptions(
          color: false,
          paper: PrintPaper.original,
          duplex: PrintDuplex.single,
          copies: 1,
        ),
      ),
      throwsA(
        isA<UiError>().having(
          (error) => _event(controller, error),
          '整批操作',
          allOf(
            containsPair('operation', 'cloudPrintUpload'),
            isNot(contains('file_index')),
          ),
        ),
      ),
    );
    expect(
      telemetry.records.where((r) => r.name == 'write_failed'),
      hasLength(1),
    );
    expect(controller.exportDiagnostics(), isNot(contains('私有文件')));
  });

  test('云盘下载及准备失败各自保留报告编号', () async {
    final telemetry = MockTelemetryClient(enabled: false);
    final controller = await start(_Backend(), telemetry: telemetry);
    final disk = controller.bhpanService!;
    for (final (operation, run) in <(String, Future<Object> Function())>[
      (
        'bhpanDownloadPreparation',
        () => disk.downloadPreparation(['句柄'], '文件'),
      ),
      (
        'bhpanDownload',
        () => disk.download(['句柄'], '文件', '/私有结果路径', false, _Transfer()),
      ),
    ]) {
      await expectLater(
        run(),
        throwsA(
          isA<UiError>().having(
            (error) => _event(controller, error)['operation'],
            '下载阶段',
            operation,
          ),
        ),
      );
    }
    expect(telemetry.records, isEmpty);
    expect(controller.exportDiagnostics(), isNot(contains('私有结果路径')));
  });

  test('普通写入失败保留操作和实际路线，仅一次写失败计数', () async {
    final telemetry = MockTelemetryClient();
    final backend = _Backend();
    final controller = await start(backend, telemetry: telemetry);
    controller.writeCoordinator.setIntent(_intent());
    final error = (await controller.writeCoordinator.confirmForUi())!.error!;
    expect(backend.commits, 1);
    final event = _event(controller, error);
    expect(event['feature'], 'bykc');
    expect(event['write_operation'], 'bykcSelectCourse');
    expect(event['route'], 'webvpn');
    final diagnostic = jsonDecode(writeFailure.diagnosticJson!);
    expect(event['diagnostic'], diagnostic);
    final failure = telemetry.records
        .where((r) => r.name == 'write_failed')
        .single;
    expect(failure.properties['error_code'], 'outcome_unknown');
    expect(failure.properties['route'], 'webvpn');
    expect(jsonDecode(failure.properties['diagnostic'] as String), diagnostic);
    expect(failure.properties, isNot(contains('issue_id')));
    expect(controller.exportDiagnostics(), isNot(contains('私有选课目标')));
  });

  test('学校资格核对失败记录一次，未发送写请求，本机输入错误不计入', () async {
    final backend = _Backend();
    final telemetry = MockTelemetryClient();
    final controller = await start(backend, telemetry: telemetry);
    const diagnostic =
        '{"source":"crates/ubaa_core/src/features/bykc/parser.rs:50",'
        '"stage":"qualification","reason":"missing_field","status":200}';
    await expectLater(
      controller.writeCoordinator.prepareForUi(
        () async => throw bridgeMapError(
          const BridgeError(
            code: BridgeErrorCode.operationConflict,
            kind: BridgeErrorKind.input,
            retryable: true,
            message: '资格预查失败',
            resolvedRoute: BridgeConnectionMode.webVpn,
            diagnosticJson: diagnostic,
          ),
        ),
        expectedOperation: WriteOperation.bykcSelectCourse,
      ),
      throwsA(
        isA<UiError>().having(
          (e) => _event(controller, e),
          '资格核对诊断',
          allOf(
            containsPair('diagnostic', jsonDecode(diagnostic)),
            containsPair('route', 'webvpn'),
            containsPair('write_operation', 'bykcSelectCourse'),
          ),
        ),
      ),
    );
    await expectLater(
      controller.writeCoordinator.prepareForUi(
        () async => throw const BackendException(UbaaErrorCode.invalidInput),
        expectedOperation: WriteOperation.bykcSelectCourse,
      ),
      throwsA(isA<UiError>()),
    );
    expect(backend.commits, 0);
    expect(
      telemetry.records
          .where((r) => r.name == 'write_completed')
          .single
          .properties['result'],
      'failure',
    );
    final failure = telemetry.records
        .where((r) => r.name == 'write_failed')
        .single;
    expect(failure.properties['route'], 'webvpn');
    expect(
      jsonDecode(failure.properties['diagnostic'] as String),
      jsonDecode(diagnostic),
    );
  });

  test('关闭账号后晚到的云盘错误及旧交付不污染当前会话', () async {
    final backend = _Backend()
      ..disk.downloadGate = Completer<BhpanDownloadReceipt>();
    final telemetry = MockTelemetryClient();
    final controller = await start(backend, telemetry: telemetry);
    final service = controller.bhpanService!;
    final deliverError = StateError('/私有文档位置');
    final recorded = controller.recordBhpanDeliveryFailure(
      service,
      deliverError,
      StackTrace.current,
    );
    expect(_event(controller, recorded)['operation'], 'bhpanDelivery');
    expect(controller.exportDiagnostics(), isNot(contains('私有文档位置')));
    final pending = expectLater(
      service.download(['句柄'], '文件', '/私有路径', false, _Transfer()),
      throwsA(isA<StateError>()),
    );
    await controller.logout();
    final before = controller.diagnostics.records.length;
    backend.disk.downloadGate!.completeError(StateError('/旧私有路径'));
    await pending;
    expect(
      controller
          .recordBhpanDeliveryFailure(service, deliverError, StackTrace.current)
          .issueId,
      isNull,
    );
    expect(controller.diagnostics.records.length, before);
    expect(
      telemetry.records.where((r) => r.properties['feature'] == 'bhpan'),
      isEmpty,
    );
  });

  test('正常提交成功纳入分母，返回的失败结果可以独立导出报告', () async {
    final backend = _Backend();
    final telemetry = MockTelemetryClient();
    final controller = await start(backend, telemetry: telemetry);
    for (final success in [true, false]) {
      final result = backend.writeResult = WriteCommitResult(
        operation: WriteOperation.bykcSelectCourse,
        success: success,
        message: '合成提交结果',
        outcomeUnknown: false,
        resolvedRoute: ConnectionMode.webvpn,
      );
      controller.writeCoordinator.setIntent(_intent());
      final outcome = (await controller.writeCoordinator.confirmForUi())!;
      expect(outcome.result, same(result));
      expect(outcome.error, isNull);
      if (!success) {
        expect(
          _event(controller, outcome.resultError!)['code'],
          'business_rejected',
        );
      }
    }
    expect(
      telemetry.records
          .where((r) => r.name == 'write_completed')
          .map((r) => r.properties['result']),
      ['success', 'failure'],
    );
    expect(backend.commits, 2);
  });
}
