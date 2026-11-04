part of 'view.dart';

extension AgendaDetails on AgendaViewState {
  Future<AgendaEditScope?> chooseScope() => showDialog<AgendaEditScope>(
    context: context,
    builder: (context) => bound(
      SimpleDialog(
        title: const Text('处理重复事项'),
        children: [
          for (final entry in {
            AgendaEditScope.thisOccurrence: '仅此次',
            AgendaEditScope.thisAndFuture: '此次及以后',
            AgendaEditScope.all: '全部',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    ),
  );
  Future<void> complete(AgendaEntry entry, bool value) {
    final token = revision;
    return change(() async {
      final local = entry.local;
      final time = agendaTime(campusDate(DateTime.now()));
      if (local != null) {
        await service.complete(local.itemId, recurrenceAt(local), value, time);
      } else {
        final old = await service.overlay(entry.school!.key);
        if (!current(token)) return;
        await service.setOverlay(
          AgendaOverlayDraft(
            key: entry.school!.key,
            completedAt: value ? time : null,
            completionOverride: true,
            hidden: old?.value.hidden ?? entry.hidden,
            note: old?.value.note ?? entry.note,
          ),
          time,
        );
      }
    });
  }

  Future<AgendaItem?> detailItem(String id, int token) async {
    try {
      final item = await service.get(id);
      return current(token) ? item : null;
    } on Object {
      if (current(token))
        UbaaFeedback.show(
          context,
          '事项读取失败，原数据已保留',
          kind: UbaaFeedbackKind.error,
        );
      return null;
    }
  }

  Future<void> details(AgendaEntry entry) async {
    final token = revision;
    final local = entry.local;
    final school = entry.school;
    var note = entry.note ?? local?.content.notes ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => bound(
        SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewInsetsOf(sheet).bottom + 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  agendaTitle(entry),
                  style: Theme.of(sheet).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('${agendaSource(entry)} · ${agendaWhen(entry)}'),
                Text(
                  entry.timing.from ??
                      (entry.timing.start ?? entry.timing.due)?.rfc3339
                          .substring(0, 10) ??
                      '无日期',
                ),
                if (school != null) ...[
                  Text('学校状态：${school.statusLabel}'),
                  Text(school.subtitle),
                  const Text('完成、隐藏与备注只保存在本机，不改变学校数据。'),
                  TextFormField(
                    initialValue: note,
                    onChanged: (value) => note = value,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '本地备注'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      if (!current(token)) return;
                      final savedNote = note;
                      Navigator.pop(sheet);
                      await change(() async {
                        final old = await service.overlay(school.key);
                        if (!current(token)) return;
                        await service.setOverlay(
                          AgendaOverlayDraft(
                            key: school.key,
                            completedAt: old?.value.completedAt,
                            completionOverride:
                                old?.value.completionOverride ?? false,
                            hidden: entry.hidden,
                            note: savedNote,
                          ),
                          agendaTime(campusDate(DateTime.now())),
                        );
                      });
                    },
                    child: const Text('保存备注'),
                  ),
                  TextButton(
                    onPressed: () {
                      if (!current(token)) return;
                      Navigator.pop(sheet);
                      widget.onOpenSchool(agendaNavigation(school.navigation));
                    },
                    child: const Text('打开原功能'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (!current(token)) return;
                      Navigator.pop(sheet);
                      await change(() async {
                        final old = await service.overlay(school.key);
                        if (!current(token)) return;
                        await service.setOverlay(
                          AgendaOverlayDraft(
                            key: school.key,
                            completedAt: old?.value.completedAt,
                            completionOverride:
                                old?.value.completionOverride ?? false,
                            hidden: !entry.hidden,
                            note: old?.value.note ?? entry.note,
                          ),
                          agendaTime(campusDate(DateTime.now())),
                        );
                      });
                    },
                    child: Text(entry.hidden ? '恢复显示' : '隐藏事项'),
                  ),
                ] else ...[
                  if (local?.content.notes case final notes?) Text(notes),
                  TextButton(
                    onPressed: () async {
                      if (!current(token)) return;
                      Navigator.pop(sheet);
                      final item = await detailItem(local!.itemId, token);
                      if (!current(token) || item == null) return;
                      final scope = item.rrule == null
                          ? AgendaEditScope.all
                          : await chooseScope();
                      if (scope != null && current(token))
                        await edit(item: item, occurrence: local, scope: scope);
                    },
                    child: const Text('编辑事项'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (!current(token)) return;
                      Navigator.pop(sheet);
                      final item = await detailItem(local!.itemId, token);
                      if (!current(token) || item == null) return;
                      final scope = item.rrule != null
                          ? await chooseScope()
                          : await showDialog<AgendaEditScope>(
                              context: context,
                              builder: (dialog) => bound(
                                AlertDialog(
                                  title: const Text('删除事项？'),
                                  content: Text(item.content.title),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialog),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(
                                        dialog,
                                        AgendaEditScope.all,
                                      ),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                      if (scope != null && current(token))
                        await change(
                          () => service.delete(
                            local.itemId,
                            scope,
                            recurrenceAt(local),
                            agendaTime(campusDate(DateTime.now())),
                          ),
                        );
                    },
                    child: const Text('删除事项'),
                  ),
                ],
                if (school?.navigation.feature != AgendaFeature.schedule &&
                    school?.navigation.feature != AgendaFeature.exam)
                  OutlinedButton(
                    onPressed: () {
                      if (!current(token)) return;
                      Navigator.pop(sheet);
                      unawaited(complete(entry, !entry.completed));
                    },
                    child: Text(entry.completed ? '重新挂起' : '标记完成'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
