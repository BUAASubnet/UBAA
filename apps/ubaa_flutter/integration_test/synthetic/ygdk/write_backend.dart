import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'backend.dart';

/// 显式内存写入验收；无FRB、账号、文件或网络调用。
class SportsWriteBackend extends SportsBackend {
  SportsWriteBackend(this.scenario);
  final String scenario;
  final active = <String>{};
  Completer<void>? commitGate;
  bool committed = false, cancelFailed = false;

  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async {
    prepared.add(input);
    final id = 'synthetic-sports-write-${prepared.length}';
    active.add(id);
    return WriteIntent(
      intentId: id,
      operation: WriteOperation.ygdkSubmit,
      targetSummary: '合成运动项目 ${input.action.itemId}',
      resolvedRoute: ConnectionMode.direct,
      warnings: const ['显式内存演练，不连接学校'],
      expiresAt: DateTime.now().add(
        Duration(seconds: scenario == 'expired' ? -1 : 120),
      ),
      requestDigest: 'synthetic-sports-write',
    );
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {
    if (scenario == 'cancel-failure' && !cancelFailed) {
      cancelFailed = true;
      throw const BackendException(UbaaErrorCode.networkError);
    }
    active.remove(intentId);
    discarded.add(intentId);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    if (!active.remove(intentId)) throw StateError('合成意图无效或重复提交');
    await commitGate?.future;
    if (scenario == 'unknown') {
      throw const BackendException(UbaaErrorCode.outcomeUnknown);
    }
    if (scenario == 'upload-failure') {
      return const WriteCommitResult(
        operation: WriteOperation.ygdkSubmit,
        success: false,
        message: '合成照片上传失败，未执行最终提交。',
        outcomeUnknown: false,
      );
    }
    committed = true;
    recordVersion++;
    return const WriteCommitResult(
      operation: WriteOperation.ygdkSubmit,
      success: true,
      message: '合成打卡已提交',
      outcomeUnknown: false,
      ygdkReceipt: YgdkSubmitReceipt(recordId: 41),
    );
  }

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) async {
    if (scenario == 'readback-failure') {
      pinnedReads.add('records:${route.name}:$page:$size');
      throw const BackendException(UbaaErrorCode.networkError);
    }
    final original = await super.loadYgdkRecordsOnRoute(
      route: route,
      page: page,
      size: size,
    );
    if (!committed) return original;
    return FeatureResult.success(
      resolvedRoute: route,
      pagination: FeaturePagination(
        page: page,
        size: size,
        total: 4,
        hasMore: false,
      ),
      details: [
        const FeatureDetail(
          title: '合成新增运动记录',
          presentation: YgdkRecordPresentation(
            recordId: 41,
            itemId: 7,
            itemName: '合成新增运动记录',
            startTime: '2026-09-09 08:00',
            endTime: '2026-09-09 09:00',
            place: '合成操场',
            imageCount: 1,
            isOpen: false,
          ),
        ),
        ...original.details,
      ],
    );
  }
}
