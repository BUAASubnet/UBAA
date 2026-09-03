import 'package:meta/meta.dart';

import '../common/error.dart';
import '../common/route.dart';
import 'catalog.dart';

enum FeatureLoadStatus { idle, loading, success, empty, stale, failure }

@immutable
class FeatureSnapshot {
  const FeatureSnapshot({
    required this.feature,
    this.status = FeatureLoadStatus.idle,
    this.summary,
    this.details = const <FeatureDetail>[],
    this.error,
    this.resolvedRoute,
    this.pagination,
    this.updatedAt,
  });

  final FeatureId feature;
  final FeatureLoadStatus status;
  final String? summary;
  final List<FeatureDetail> details;
  final UiError? error;

  /// Core 对本次读取实际解析出的路线；不能用配置策略替代。
  final ConnectionMode? resolvedRoute;

  /// Core 返回的服务端分页元数据；只对支持分页的 typed 查询存在。
  final FeaturePagination? pagination;
  final DateTime? updatedAt;

  FeatureSnapshot copyWith({
    FeatureLoadStatus? status,
    String? summary,
    List<FeatureDetail>? details,
    UiError? error,
    ConnectionMode? resolvedRoute,
    FeaturePagination? pagination,
    DateTime? updatedAt,
    bool clearError = false,
    bool clearSummary = false,
    bool clearDetails = false,
    bool clearResolvedRoute = false,
    bool clearPagination = false,
  }) => FeatureSnapshot(
    feature: feature,
    status: status ?? this.status,
    summary: clearSummary ? null : (summary ?? this.summary),
    details: clearDetails ? const <FeatureDetail>[] : (details ?? this.details),
    error: clearError ? null : (error ?? this.error),
    resolvedRoute: clearResolvedRoute
        ? null
        : (resolvedRoute ?? this.resolvedRoute),
    pagination: clearPagination ? null : (pagination ?? this.pagination),
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// 服务端分页的稳定展示元数据。页码按用户可见的 1-based 语义表达。
@immutable
class FeaturePagination {
  const FeaturePagination({
    required this.page,
    required this.size,
    required this.total,
    this.totalPages,
    this.hasMore,
  });

  final int page;
  final int size;
  final int total;
  final int? totalPages;
  final bool? hasMore;

  int get effectiveTotalPages {
    if (totalPages case final value? when value > 0) return value;
    if (size <= 0 || total <= 0) return 0;
    return (total + size - 1) ~/ size;
  }
}

/// 首页加载结果。每个功能独立返回，避免单个上游故障遮蔽其他卡片。
@immutable
class FeatureResult {
  const FeatureResult.success({
    this.summary,
    this.details = const <FeatureDetail>[],
    this.resolvedRoute,
    this.pagination,
  }) : isEmpty = false,
       error = null;

  const FeatureResult.empty({this.resolvedRoute, this.pagination})
    : summary = null,
      details = const <FeatureDetail>[],
      isEmpty = true,
      error = null;

  const FeatureResult.failure(this.error)
    : summary = null,
      details = const <FeatureDetail>[],
      resolvedRoute = null,
      pagination = null,
      isEmpty = false;

  final String? summary;
  final List<FeatureDetail> details;

  /// Core 对本次读取实际解析出的路线；失败或未执行时可以为空。
  final ConnectionMode? resolvedRoute;
  final FeaturePagination? pagination;
  final bool isEmpty;
  final UiError? error;
}

/// 只读详情页使用的稳定展示模型，不携带原始上游载荷。
@immutable
class FeatureDetail {
  const FeatureDetail({
    required this.title,
    this.subtitle,
    this.fields = const <FeatureField>[],
  });

  final String title;
  final String? subtitle;
  final List<FeatureField> fields;
}

/// 详情卡片中的标签和值；值必须来自 bridge 白名单 DTO。
@immutable
class FeatureField {
  const FeatureField({required this.label, required this.value});

  final String label;
  final String value;
}
