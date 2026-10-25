import '../common/route.dart';

enum IhomeScope { public, mine, followed, appraised }

enum IhomeFilter { all, newest, oldest, replied, unreplied, replyTime }

enum IhomeReaction { follow, support }

class IhomeQuery {
  const IhomeQuery({
    required this.scope,
    required this.page,
    required this.limit,
    required this.keyword,
    required this.filter,
    required this.categoryId,
  });
  final IhomeScope scope;
  final int page;
  final int limit;
  final String keyword;
  final IhomeFilter filter;
  final int? categoryId;
}

class IhomePage {
  const IhomePage({
    required this.entries,
    required this.page,
    required this.lastPage,
    required this.total,
  });
  final List<IhomeEntry> entries;
  final int page;
  final int lastPage;
  final int total;
}

class IhomeEntry {
  const IhomeEntry({required this.appeal, required this.evaluation});
  final IhomeAppeal appeal;
  final IhomeEvaluation? evaluation;
}

class IhomeAppeal {
  const IhomeAppeal({
    required this.id,
    required this.content,
    required this.status,
    required this.category,
    required this.publishedAt,
    required this.departments,
    required this.isMine,
    required this.isFollowed,
    required this.isSupported,
    required this.followCount,
    required this.supportCount,
    required this.replies,
    required this.evaluations,
    required this.history,
  });
  final int id;
  final String content;
  final String status;
  final String category;
  final String publishedAt;
  final List<String> departments;
  final bool isMine;
  final bool? isFollowed;
  final bool? isSupported;
  final int? followCount;
  final int? supportCount;
  final List<IhomeReply> replies;
  final List<IhomeEvaluation> evaluations;
  final List<IhomeHistory> history;
}

class IhomeReply {
  const IhomeReply({
    required this.content,
    required this.department,
    required this.createdAt,
  });
  final String content;
  final String department;
  final String createdAt;
}

class IhomeHistory {
  const IhomeHistory({required this.content, required this.createdAt});
  final String content;
  final String createdAt;
}

class IhomeEvaluation {
  const IhomeEvaluation({
    required this.id,
    required this.department,
    required this.speed,
    required this.satisfaction,
    required this.degree,
    required this.content,
    required this.createdAt,
  });
  final int id;
  final String department;
  final int speed;
  final int satisfaction;
  final int degree;
  final String content;
  final String createdAt;
}

class IhomeCategory {
  const IhomeCategory({required this.id, required this.name});
  final int id;
  final String name;
}

class IhomeConfig {
  const IhomeConfig({
    required this.supportEnabled,
    required this.supportLabel,
    required this.categories,
  });
  final bool supportEnabled;
  final String supportLabel;
  final List<IhomeCategory> categories;
}

class IhomeNotice {
  const IhomeNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
  });
  final int id;
  final String title;
  final String content;
  final String date;
}

class IhomeResult<T> {
  const IhomeResult(this.data, this.route);
  final T data;
  final ConnectionMode route;
}

/// iHome 使用独立类型化能力，入口仅位于校园服务，不加入首页自动请求。
abstract interface class IhomeService {
  Future<IhomeResult<IhomePage>> page(IhomeQuery query);
  Future<IhomeResult<IhomeAppeal>> detail(int id, {bool mine = false});
  Future<IhomeResult<IhomeConfig>> config();
  Future<IhomeResult<List<IhomeNotice>>> notices();
  Future<IhomeResult<IhomeNotice>> notice(int id);
  Future<IhomeResult<IhomeAppeal>> setReaction(
    int id,
    IhomeReaction reaction,
    bool enabled,
    ConnectionMode expectedRoute,
  );
}
