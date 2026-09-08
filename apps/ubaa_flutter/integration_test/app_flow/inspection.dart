part of '../app_flow_test.dart';

// 仅供显式人工巡检入口使用；全部业务数据为合成数据，不创建真实客户端。
final class _InspectionBackend extends _AllWritesIntegrationBackend {
  _InspectionBackend({
    String state = const String.fromEnvironment(
      'UBAA_UI_STATE',
      defaultValue: 'normal',
    ),
  }) : _state = state;

  final String _state;
  final Map<String, int> _inspectionLoads = <String, int>{};

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    // 保留基类的认证检查、计数和 typed 写操作目标。
    final original = await super.loadFeature(feature);
    final key = '${feature.name}/${query.view.name}';
    final count = _inspectionLoads.update(
      key,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    if (_state == 'loading') {
      await Future<void>.delayed(const Duration(seconds: 8));
    }
    if ((_state == 'first-error' && count == 1) ||
        (_state == 'stale' && count > 1)) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    if (_state == 'empty') {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    final details = _details(feature, query, original.details);
    // 大量模式只检验只读密度，不复制同一目标的写 action。
    final expanded = _state == 'many' && details.isNotEmpty
        ? List<FeatureDetail>.generate(40, (index) {
            final item = details[index % details.length];
            return FeatureDetail(
              title: '${item.title}（合成条目 ${index + 1}）',
              subtitle: item.subtitle,
              fields: item.fields,
              presentation: item.presentation,
              readNavigation: item.readNavigation,
            );
          })
        : details;
    final paged =
        <FeatureQueryView>{
          FeatureQueryView.libbookBookings,
          FeatureQueryView.cgyyOrders,
          FeatureQueryView.ygdkRecords,
        }.contains(query.view) ||
        (feature == FeatureId.bykc && query.view == FeatureQueryView.summary);
    if (query.size <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final page = query.page <= 0 ? 1 : query.page;
    if (page <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final visible = paged
        ? expanded.skip((page - 1) * query.size).take(query.size).toList()
        : expanded;
    final pagination = paged
        ? FeaturePagination(
            page: page,
            size: query.size,
            total: expanded.length,
            hasMore: page * query.size < expanded.length,
          )
        : null;
    if (visible.isEmpty) {
      return FeatureResult.empty(
        resolvedRoute: ConnectionMode.direct,
        pagination: pagination,
      );
    }
    return FeatureResult.success(
      summary:
          feature == FeatureId.ygdk && query.view == FeatureQueryView.summary
          ? '学期进度 8/30'
          : '${expanded.length} 项 · 合成巡检数据',
      details: visible,
      resolvedRoute: ConnectionMode.direct,
      pagination: pagination,
    );
  }

  String _day(DateTime? date) {
    if (date == null) throw const BackendException(UbaaErrorCode.invalidInput);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return value;
  }

  FeatureDetail _item(
    String title,
    Map<String, String> fields, {
    String? subtitle,
    FeaturePresentation? presentation,
    FeatureReadNavigation? readNavigation,
    List<FeatureAction> actions = const <FeatureAction>[],
  }) => FeatureDetail(
    title: _state == 'long' ? '$title——跨学科探索与实践中的长标题展示和换行检查' : title,
    subtitle: subtitle,
    fields: fields.entries
        .map((entry) => FeatureField(label: entry.key, value: entry.value))
        .toList(growable: false),
    actions: actions,
    presentation: presentation,
    readNavigation: readNavigation,
  );

  List<FeatureDetail> _details(
    FeatureId feature,
    FeatureQuery q,
    List<FeatureDetail> original,
  ) {
    final v = q.view;
    switch (feature) {
      case FeatureId.schedule:
      case FeatureId.exam:
      case FeatureId.grades:
      case FeatureId.classroom:
        return _academicDetails(feature, q);
      case FeatureId.spoc:
      case FeatureId.judge:
        final judge = feature == FeatureId.judge;
        if (v == FeatureQueryView.judgeBatchDetails) {
          return [
            for (final key in q.judgeKeys)
              ..._details(
                FeatureId.judge,
                FeatureQuery(
                  view: FeatureQueryView.judgeDetail,
                  courseId: key.courseId,
                  assignmentId: key.assignmentId,
                ),
                original,
              ),
          ];
        }
        final detail =
            v == FeatureQueryView.spocDetail ||
            v == FeatureQueryView.judgeDetail ||
            v == FeatureQueryView.judgeBatchDetails;
        return [
          _item(judge ? '实验二：树与递归' : '第三章：算法复杂度练习', {
            '课程编号': q.courseId ?? 'course-demo',
            '作业编号': q.assignmentId ?? 'assignment-demo',
            if (!judge) '教师': '示例教师甲',
            '开始': '2026-09-07 08:00',
            '截止': '2026-09-14 23:59',
            '状态': '未提交',
            if (judge) ...{'进度': '2/5', '我的得分': '40'} else '得分': '尚未评分',
            if (detail)
              '作业内容': '这是一份合成作业。请阅读题目，完成推导与程序设计，并说明边界条件。长段落用于检查内容密度与换行。',
          }, subtitle: '数据结构与算法（合成课程）'),
          if (judge && detail)
            _item('题目一：二叉树遍历', {'状态': '已通过', '得分': '20', '满分': '20'}),
          if (judge && detail)
            _item('题目二：递归边界', {'状态': '未通过', '得分': '0', '满分': '20'}),
        ];
      case FeatureId.signin:
        final completed = committedOperations.contains(
          WriteOperation.signinPerform,
        );
        if ((v == FeatureQueryView.signinCompleted && !completed) ||
            (v == FeatureQueryView.signinPending && completed)) {
          return [];
        }
        return [
          _item(
            '数据结构与算法 · 课堂签到',
            {'课程 ID': 'signin-course', '签到状态': completed ? '已签到' : '未签到'},
            subtitle: '示例教师甲',
            actions: completed ? const [] : original.first.actions,
          ),
        ];
      case FeatureId.evaluation:
        final evaluated = committedOperations.contains(
          WriteOperation.evaluationSubmitCourses,
        );
        if (v == FeatureQueryView.evaluationPending && evaluated) return [];
        return [
          _item(
            '离散数学',
            {
              '状态': evaluated ? '已评' : '待评',
              '课程 ID':
                  'task-evaluation_questionnaire-evaluation_K-EVAL_teacher-evaluation',
            },
            subtitle: '示例教师乙',
            actions: evaluated ? const [] : original.first.actions,
          ),
        ];
      case FeatureId.bykc:
        if (v == FeatureQueryView.bykcProfile) {
          return [
            _item('博雅个人资料', {
              '用户 ID': '99',
              '姓名': '合成同学',
              '学号': '2020000099',
              '学院': '示例学院',
            }),
          ];
        }
        if (v == FeatureQueryView.bykcStatistics) {
          return [
            _item('科学素养', {'要求数量': '8', '通过数量': '5', '达标': '否'}),
            _item('文化艺术', {'要求数量': '4', '通过数量': '4', '达标': '是'}),
          ];
        }
        return [
          _item(
            '从星空到深空：航天探索讲座',
            {
              '课程 ID': '42',
              '地点': '合成报告厅',
              '状态': _bykcSelected ? '已选' : '可选',
              '已选人数': '36',
              '容量': '80',
              '开始': '2026-09-12 14:00',
              '结束': '2026-09-12 16:00',
              '选课截止': '2026-09-11 18:00',
              '退选截止': '2026-09-11 12:00',
              if (v == FeatureQueryView.bykcChosenCourses) ...{
                '签到状态': '未签到',
                '可签到': '是',
                '可签退': '是',
                '位置要求': '无需位置',
              },
            },
            subtitle: '科学素养 · 示例教师丙',
            actions: original.first.actions,
          ),
        ];
      case FeatureId.libbook:
        if (v == FeatureQueryView.summary) {
          return [
            _item('合成校区图书馆', {
              '馆 ID': 'library-1',
              '空闲座位': '126',
              '总座位': '320',
              '楼层数': '4',
            }),
          ];
        }
        if (v == FeatureQueryView.libbookAreas) {
          return [
            _item('二层安静阅览区', {
              '分区 ID': 'area-1',
              '楼层 ID': 'floor-2',
              '空闲座位': '42',
              '总座位': '80',
            }, subtitle: '合成校区图书馆'),
          ];
        }
        if (v == FeatureQueryView.libbookAreaDetail) {
          return [
            _item('二层安静阅览区', {
              '分区 ID': 'area-1',
              '可用日期': '2026-09-02、2026-09-03',
              '时段': '10:00–12:00、14:00–16:00',
            }),
          ];
        }
        if (v == FeatureQueryView.libbookBookings) {
          return [
            _item(
              '合成图书馆 · A018',
              {
                '预约 ID': 'booking-1',
                '座位': 'A018',
                '日期': '2026-09-02',
                '时段': '10:00–12:00',
                '状态码': '1',
                '状态': '有效',
                '可取消': '是',
              },
              subtitle: '二层安静阅览区',
              actions: [
                LibbookCancelAction(
                  bookingId: 'booking-1',
                  page: q.page <= 0 ? 1 : q.page,
                  limit: q.size,
                  eligibility: ActionEligibility.allowed,
                ),
              ],
            ),
          ];
        }
        final reserve = LibbookReserveAction(
          areaId: _required(q.areaId),
          seatId: 'seat-1',
          day: _day(q.date),
          segment: _required(q.segment),
          startTime: _required(q.startTime),
          endTime: _required(q.endTime),
          eligibility: ActionEligibility.allowed,
        );
        return [
          _item(
            '靠窗座位 A018',
            {
              '分区 ID': reserve.areaId,
              '座位 ID': reserve.seatId,
              '日期': reserve.day,
              '时段': reserve.segment,
              '开始时间': reserve.startTime,
              '结束时间': reserve.endTime,
              '可预约': '是',
              '状态': '空闲',
            },
            actions: [reserve],
          ),
        ];
      case FeatureId.cgyy:
        if (v == FeatureQueryView.summary) {
          return [
            _item('合成研讨楼', {
              '站点 ID': '3',
              '校区': '合成校区',
              '座位数': '24',
              '空间数': '6',
              '开放开始': '2026-09-01',
              '开放结束': '2026-12-31',
            }),
          ];
        }
        if (v == FeatureQueryView.cgyyPurposeTypes) {
          return [
            _item('小组研讨', {'用途编号': '1', '来源': '研讨室用途'}),
          ];
        }
        if (v == FeatureQueryView.cgyyLockCode) {
          return [
            _item('门锁状态', {'可用': '是'}),
          ];
        }
        if (v == FeatureQueryView.cgyyOrders ||
            v == FeatureQueryView.cgyyOrderDetail) {
          return [
            _item('合成研讨楼 · 4 号研讨室', {
              '订单编号': '17',
              '校区': '合成校区',
              '日期': '2099-01-01',
              '开始': '2099-01-01 10:00:00',
              '结束': '2099-01-01 11:00:00',
              '用途': '小组研讨',
              '参与人数': '2',
              '订单状态': '1',
              '审核状态': '1',
            }, actions: original.last.actions),
          ];
        }
        if (q.siteId == null || q.siteId! <= 0) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        final reservationDate = _day(q.date);
        return [
          _item(
            '4 号研讨室',
            {
              '站点 ID': '${q.siteId}',
              '日期': reservationDate,
              '空间 ID': '4',
              '空间组 ID': '9',
              '时段 ID': '5',
              '开始时间': '10:00',
              '结束时间': '11:00',
              '可预约': '是',
            },
            actions: [
              CgyyReserveAction(
                venueSiteId: q.siteId!,
                reservationDate: reservationDate,
                spaceId: 4,
                timeId: 5,
                venueSpaceGroupId: 9,
                timeOrdinal: 0,
                eligibility: ActionEligibility.allowed,
              ),
            ],
          ),
        ];
      case FeatureId.ygdk:
        if (v == FeatureQueryView.ygdkRecords) {
          return [
            _item('操场慢跑', {
              '记录编号': '101',
              '开始时间': '2026-09-07 17:00',
              '结束时间': '2026-09-07 17:30',
              '地点': '合成田径场',
              '公开状态': '不公开',
              '图片数量': '1',
            }, subtitle: '2026-09-07'),
          ];
        }
        return [
          _item('操场慢跑', {
            '项目编号': '7',
            '类型': '1',
          }, actions: original.first.actions),
        ];
    }
  }
}
