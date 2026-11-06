import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/bhpan/write_flow.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

class FlowFiles implements BhpanService {
  @override
  Future<WriteIntent> prepare(BhpanMutation request) async => WriteIntent(
    intentId: 'intent-1',
    operation: WriteOperation.bhpan,
    targetSummary: '上传到个人文档库',
    resolvedRoute: ConnectionMode.direct,
    warnings: const ['文件内容将上传到云端'],
    expiresAt: DateTime(2030),
    requestDigest: 'synthetic',
  );

  @override
  BhpanTransferTask createTransfer() => throw UnimplementedError();
  @override
  Future<BhpanPage> read(BhpanRead query) => throw UnimplementedError();
  @override
  Future<void> login() async {}
  @override
  Future<BhpanCapabilities> capabilities() => throw UnimplementedError();
  @override
  Future<BhpanSize> size(String item) => throw UnimplementedError();
  @override
  Future<String> suggestName(String parent, String name) =>
      throw UnimplementedError();
  @override
  Future<List<BhpanShare>> shares({String? item}) => throw UnimplementedError();
  @override
  Future<String> shareLink(String share) => throw UnimplementedError();
  @override
  Future<BhpanDownloadPreparation> downloadPreparation(
    List<String> handles,
    String name,
  ) => throw UnimplementedError();
  @override
  Future<BhpanDownloadReceipt> download(
    List<String> handles,
    String name,
    String path,
    bool overwrite,
    BhpanTransferTask transfer,
  ) => throw UnimplementedError();
}

void main() {
  testWidgets('发起界面已确认但 Core 有 warnings 时仍显示确认框', (tester) async {
    final generation = ValueNotifier(0);
    addTearDown(generation.dispose);
    var committed = false;
    const request = BhpanMutation(BhpanMutationKind.upload, target: 'root');
    final intent = WriteIntent(
      intentId: 'intent-1',
      operation: WriteOperation.bhpan,
      targetSummary: '上传到个人文档库',
      resolvedRoute: ConnectionMode.direct,
      warnings: const ['文件内容将上传到云端'],
      expiresAt: DateTime(2030),
      requestDigest: 'synthetic',
    );
    final outcome = const WriteOutcome(
      operation: WriteOperation.bhpan,
      message: '已完成',
      result: WriteCommitResult(
        operation: WriteOperation.bhpan,
        success: true,
        outcomeUnknown: false,
        message: '已完成',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                await runBhpanWriteFlow(
                  context: context,
                  request: request,
                  service: FlowFiles(),
                  generation: generation,
                  run: (_, {required expectedOperation}) async => intent,
                  confirm: () async {
                    committed = true;
                    return outcome;
                  },
                  cancel: () async {},
                  state: WriteState.idle,
                  isCurrent: () => true,
                  style: const BhpanWriteStyle(confirmed: true),
                );
              },
              child: const Text('提交'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('上传文件'), findsOneWidget);
    expect(committed, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, '上传'));
    await tester.pumpAndSettle();
    expect(committed, isTrue);
  });
}
