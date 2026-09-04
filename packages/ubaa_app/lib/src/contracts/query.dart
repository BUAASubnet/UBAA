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
