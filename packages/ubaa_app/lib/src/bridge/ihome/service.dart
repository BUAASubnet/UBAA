import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/mapping.dart' show bridgeToConnectionMode;

/// 桥接错误统一投影为可展示的安全领域错误。
class BridgeIhomeService implements IhomeService {
  BridgeIhomeService(this.client);
  final BridgeClient client;
  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on BridgeError catch (e) {
      throw UiError(
        title: "iHome 请求失败",
        message: e.code == "outcome_unknown"
            ? "操作结果未确认，请刷新详情后核对"
            : "读取失败，请稍后重试",
        code: UbaaErrorCode.values.firstWhere(
          (v) => v.name == e.code.name,
          orElse: () => UbaaErrorCode.upstreamUnavailable,
        ),
      );
    }
  }

  @override
  Future<IhomeResult<IhomePage>> page(IhomeQuery q) => _call(() async {
    final r = await client.ihomePage(
      query: BridgeIhomeQuery(
        scope: BridgeIhomeScope.values[q.scope.index],
        page: q.page,
        limit: q.limit,
        keyword: q.keyword,
        filter: BridgeIhomeFilter.values[q.filter.index],
        categoryId: q.categoryId,
      ),
    );
    return IhomeResult(
      _mapIhomePage(r.data),
      bridgeToConnectionMode(r.route.resolvedRoute),
    );
  });
  @override
  Future<IhomeResult<IhomeAppeal>> detail(int id, {bool mine = false}) =>
      _call(() async {
        final r = await client.ihomeDetail(id: id, mine: mine);
        return IhomeResult(
          _mapIhomeAppeal(r.data),
          bridgeToConnectionMode(r.route.resolvedRoute),
        );
      });
  @override
  Future<IhomeResult<IhomeConfig>> config() => _call(() async {
    final r = await client.ihomeConfig();
    return IhomeResult(
      _mapIhomeConfig(r.data),
      bridgeToConnectionMode(r.route.resolvedRoute),
    );
  });
  @override
  Future<IhomeResult<List<IhomeNotice>>> notices() => _call(() async {
    final r = await client.ihomeNotices();
    return IhomeResult(
      r.data.map(_mapIhomeNotice).toList(),
      bridgeToConnectionMode(r.route.resolvedRoute),
    );
  });
  @override
  Future<IhomeResult<IhomeNotice>> notice(int id) => _call(() async {
    final r = await client.ihomeNotice(id: id);
    return IhomeResult(
      _mapIhomeNotice(r.data),
      bridgeToConnectionMode(r.route.resolvedRoute),
    );
  });
  @override
  Future<IhomeResult<IhomeAppeal>> setReaction(
    int id,
    IhomeReaction reaction,
    bool enabled,
    ConnectionMode expectedRoute,
  ) => _call(() async {
    final r = await client.ihomeSetReaction(
      id: id,
      reaction: BridgeIhomeReaction.values[reaction.index],
      enabled: enabled,
      expectedRoute: BridgeConnectionMode.values[expectedRoute.index],
    );
    return IhomeResult(
      _mapIhomeAppeal(r.data),
      bridgeToConnectionMode(r.route.resolvedRoute),
    );
  });
}

IhomePage _mapIhomePage(BridgeIhomePage v) => IhomePage(
  entries: v.entries.map(_mapIhomeEntry).toList(),
  page: v.page,
  lastPage: v.lastPage,
  total: v.total,
);
IhomeEntry _mapIhomeEntry(BridgeIhomeEntry v) => IhomeEntry(
  appeal: _mapIhomeAppeal(v.appeal),
  evaluation: v.evaluation == null ? null : _mapIhomeEvaluation(v.evaluation!),
);
IhomeAppeal _mapIhomeAppeal(BridgeIhomeAppeal v) => IhomeAppeal(
  id: v.id,
  content: v.content,
  status: v.status,
  category: v.category,
  publishedAt: v.publishedAt,
  departments: v.departments,
  isMine: v.isMine,
  isFollowed: v.isFollowed,
  isSupported: v.isSupported,
  followCount: v.followCount,
  supportCount: v.supportCount,
  replies: v.replies.map(_mapIhomeReply).toList(),
  evaluations: v.evaluations.map(_mapIhomeEvaluation).toList(),
  history: v.history.map(_mapIhomeHistory).toList(),
);
IhomeReply _mapIhomeReply(BridgeIhomeReply v) => IhomeReply(
  content: v.content,
  department: v.department,
  createdAt: v.createdAt,
);
IhomeHistory _mapIhomeHistory(BridgeIhomeHistory v) =>
    IhomeHistory(content: v.content, createdAt: v.createdAt);
IhomeEvaluation _mapIhomeEvaluation(BridgeIhomeEvaluation v) => IhomeEvaluation(
  id: v.id,
  department: v.department,
  speed: v.speed,
  satisfaction: v.satisfaction,
  degree: v.degree,
  content: v.content,
  createdAt: v.createdAt,
);
IhomeCategory _mapIhomeCategory(BridgeIhomeCategory v) =>
    IhomeCategory(id: v.id, name: v.name);
IhomeConfig _mapIhomeConfig(BridgeIhomeConfig v) => IhomeConfig(
  supportEnabled: v.supportEnabled,
  supportLabel: v.supportLabel,
  categories: v.categories.map(_mapIhomeCategory).toList(),
);
IhomeNotice _mapIhomeNotice(BridgeIhomeNotice v) =>
    IhomeNotice(id: v.id, title: v.title, content: v.content, date: v.date);
