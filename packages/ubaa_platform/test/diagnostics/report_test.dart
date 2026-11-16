import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('分享附件保持 JSON 与中文的 UTF-8 内容且不提前报告发送成功', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DiagnosticReportExporter.channel, (
          call,
        ) async {
          received = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DiagnosticReportExporter.channel, null),
    );
    const report =
        '{"schema_version":3,"events":[{"upstream_message":"报名失败，该课程人数已满"}]}';
    final result = await const DiagnosticReportExporter(
      operatingSystem: 'android',
    ).export(report);
    expect(result, isNull);
    expect(received!.method, 'shareReport');
    final args = received!.arguments as Map;
    expect(utf8.decode((args['bytes'] as List).cast<int>()), report);
    expect(args['name'], matches(r'^UBAA-report-[0-9]+\.json$'));
  });
}
