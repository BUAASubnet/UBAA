import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'preview_academic.dart';

class PreviewIhome implements IhomeService {
  PreviewIhome(this.state);
  final String state;
  final followed = <int>{}, supported = <int>{};
  final counts = <String, int>{};
  Future<void> gate(String key) async {
    final count = counts.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (state == 'loading') {
      await Future<void>.delayed(const Duration(seconds: 8));
    }
    if (state == 'first-error' && count == 1 || state == 'stale' && count > 1) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
  }

  IhomeAppeal appeal(int id) => IhomeAppeal(
    id: id,
    content: '合成校园服务建议 $id${state == 'long' ? '：希望增加学习空间和休息区域。' * 15 : ''}',
    status: '已回复',
    category: '合成生活服务',
    publishedAt: previewDay(DateTime.now()),
    departments: const ['合成服务中心'],
    isMine: id.isEven,
    isFollowed: followed.contains(id),
    isSupported: supported.contains(id),
    followCount: followed.contains(id) ? 1 : 0,
    supportCount: supported.contains(id) ? 1 : 0,
    replies: const [
      IhomeReply(
        content: '合成回复：已收到建议，感谢反馈。',
        department: '合成服务中心',
        createdAt: '合成日期',
      ),
    ],
    evaluations: const [],
    history: const [IhomeHistory(content: '合成处理记录', createdAt: '合成日期')],
  );
  @override
  Future<IhomeResult<IhomePage>> page(IhomeQuery q) async {
    await gate('page/${q.scope}/${q.page}/${q.keyword}');
    final rows =
        [
              for (
                var i = 1;
                i <=
                    (state == 'empty'
                        ? 0
                        : state == 'many'
                        ? 60
                        : 8);
                i++
              )
                appeal(i),
            ]
            .where(
              (a) =>
                  a.content.contains(q.keyword) &&
                  (q.scope != IhomeScope.mine || a.isMine) &&
                  (q.scope != IhomeScope.followed || a.isFollowed == true),
            )
            .toList();
    return IhomeResult(
      IhomePage(
        entries: rows
            .skip((q.page - 1) * q.limit)
            .take(q.limit)
            .map(
              (a) => IhomeEntry(
                appeal: a,
                evaluation: q.scope == IhomeScope.appraised
                    ? IhomeEvaluation(
                        id: a.id,
                        department: '合成服务中心',
                        speed: 5,
                        satisfaction: 5,
                        degree: 5,
                        content: '合成评价',
                        createdAt: '合成日期',
                      )
                    : null,
              ),
            )
            .toList(),
        page: q.page,
        lastPage: (rows.length / q.limit).ceil().clamp(1, 100),
        total: rows.length,
      ),
      ConnectionMode.direct,
    );
  }

  @override
  Future<IhomeResult<IhomeConfig>> config() async => const IhomeResult(
    IhomeConfig(
      supportEnabled: true,
      supportLabel: '支持',
      categories: [IhomeCategory(id: 1, name: '合成生活服务')],
    ),
    ConnectionMode.direct,
  );
  @override
  Future<IhomeResult<IhomeAppeal>> detail(int id, {bool mine = false}) async {
    await gate('detail/$id');
    return IhomeResult(appeal(id), ConnectionMode.direct);
  }

  @override
  Future<IhomeResult<List<IhomeNotice>>> notices() async => IhomeResult(
    state == 'empty' ? [] : [(await notice(1)).data],
    ConnectionMode.direct,
  );
  @override
  Future<IhomeResult<IhomeNotice>> notice(int id) async => IhomeResult(
    IhomeNotice(
      id: id,
      title: '合成校园公告',
      content: '这是人工预览使用的合成公告正文。',
      date: previewDay(DateTime.now()),
    ),
    ConnectionMode.direct,
  );
  @override
  Future<IhomeResult<IhomeAppeal>> setReaction(
    int id,
    IhomeReaction reaction,
    bool enabled,
    ConnectionMode expectedRoute,
  ) async {
    final set = reaction == IhomeReaction.follow ? followed : supported;
    enabled ? set.add(id) : set.remove(id);
    return IhomeResult(appeal(id), ConnectionMode.direct);
  }
}
