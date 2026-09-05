import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 支持领域筛选/服务端分页的可选 backend 能力。
///
/// 保留与 [UbaaBackend] 分离的接口，确保旧版 fake backend 不必伪造查询能力；
/// 生产 bridge backend 实现该接口并将参数 typed 传入 Core。
abstract interface class FeatureQueryBackend {
  Future<FeatureResult> loadFeatureQuery(FeatureId feature, FeatureQuery query);
}

/// 场馆取消后只在 intent 已确认路线上执行列表与详情双回读。
///
/// 实现必须把 [route] 直接交给 Bridge/Core 的固定路线 facade，不得先按
/// 当前 Auto 策略读取、再对返回路线做事后比较。
abstract interface class CgyyCancellationReadbackBackend {
  Future<FeatureResult> loadCgyyOrdersOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  });

  Future<FeatureResult> loadCgyyOrderDetailOnRoute({
    required ConnectionMode route,
    required int orderId,
  });
}

/// 阳光打卡写后两项只读刷新各自保存的展示状态。
///
/// 该状态不携带收据、记录匹配或成功证明；[overview] 与 [records]
/// 只表示两个独立 best-effort 读取的最新安全快照。
@immutable
class YgdkReadbackState {
  YgdkReadbackState({required this.overview, required this.records})
    : assert(overview.feature == FeatureId.ygdk),
      assert(records.feature == FeatureId.ygdk);

  const YgdkReadbackState.empty()
    : overview = const FeatureSnapshot(feature: FeatureId.ygdk),
      records = const FeatureSnapshot(feature: FeatureId.ygdk);

  final FeatureSnapshot overview;
  final FeatureSnapshot records;
}

/// 阳光打卡提交后只在 intent 已确认路线读取概览与记录首页。
///
/// 冻结来源未定义本次写入与记录页之间的严格关联规则，因此本能力
/// 只更新展示快照，不返回也不推导“已核对”证明。
abstract interface class YgdkSubmissionReadbackBackend {
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  });

  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  });
}

/// 评教提交后只在 intent 已确认的原路线刷新课程 authority。
///
/// 回读只更新安全展示状态，不得把 `outcomeUnknown` 升级为成功，
/// 也不得重发评教写请求。
abstract interface class EvaluationSubmissionReadbackBackend {
  Future<FeatureResult> loadEvaluationOnRoute({required ConnectionMode route});
}
