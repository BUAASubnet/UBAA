part of '../bridge_backend.dart';

Future<FeatureResult> _loadBykcFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.bykc:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.bykcCourses(
            // Core 的分页合同为 1-based；UI 的通用查询默认从 0 开始，
            // 因此这里在 bridge 边界显式收敛为首个有效页。
            page: query.page <= 0 ? 1 : query.page,
            size: query.size.clamp(1, 100),
            all: true,
          );
          final details = result.data.content
              .map(
                (item) => FeatureDetail(
                  title: item.courseName,
                  subtitle: item.courseTeacher,
                  actions: <FeatureAction>[
                    BykcSelectAction(
                      courseId: item.id,
                      eligibility: _toBykcActionEligibility(
                        item.selectEligibility,
                      ),
                    ),
                  ],
                  fields: _compactFields(<FeatureField?>[
                    _field('课程 ID', item.id.toString()),
                    _field('地点', item.coursePosition),
                    _field('状态', item.status.name),
                    item.courseCurrentCount == null
                        ? null
                        : _field('已选人数', '${item.courseCurrentCount}'),
                    item.courseMaxCount == null
                        ? null
                        : _field('容量', '${item.courseMaxCount}'),
                    _field('选课截止', item.courseSelectEndDate),
                    _field('退选截止', item.courseCancelEndDate),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.content.length,
            '门博雅课程',
            details: details,
            pagination: _pagination(
              page: result.data.number,
              size: result.data.size,
              total: result.data.totalElements,
              totalPages: result.data.totalPages,
            ),
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.bykcDetail:
          final id = _requiredPositiveQueryInt(query.courseId, '课程 ID');
          final result = await client.bykcCourseDetail(id: id);
          final item = result.data;
          return FeatureResult.success(
            summary: '博雅课程详情',
            details: <FeatureDetail>[
              FeatureDetail(
                title: item.courseName,
                subtitle: item.courseTeacher,
                actions: <FeatureAction>[
                  BykcSelectAction(
                    courseId: item.id,
                    eligibility: _toBykcActionEligibility(
                      item.selectEligibility,
                    ),
                  ),
                ],
                fields: _compactFields(<FeatureField?>[
                  _field('课程 ID', item.id.toString()),
                  _field('地点', item.coursePosition),
                  _field('状态', item.status.name),
                  item.courseCurrentCount == null
                      ? null
                      : _field('已选人数', '${item.courseCurrentCount}'),
                  item.courseMaxCount == null
                      ? null
                      : _field('容量', '${item.courseMaxCount}'),
                  _field('开始', item.courseStartDate),
                  _field('结束', item.courseEndDate),
                  _field('选课开始', item.courseSelectStartDate),
                  _field('选课截止', item.courseSelectEndDate),
                  _field('退选截止', item.courseCancelEndDate),
                  _field(
                    '已选',
                    item.selected == null
                        ? null
                        : item.selected!
                        ? '是'
                        : '否',
                  ),
                ]),
              ),
            ],
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.bykcProfile:
          final result = await client.bykcProfile();
          final item = result.data;
          return FeatureResult.success(
            summary: '博雅个人资料',
            details: <FeatureDetail>[
              FeatureDetail(
                title: item.realName ?? '博雅个人资料',
                fields: _compactFields(<FeatureField?>[
                  _field('用户 ID', item.id.toString()),
                  _field('姓名', item.realName),
                  _field('学号', item.studentNo),
                  _field('学院', item.collegeName),
                ]),
              ),
            ],
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.bykcChosenCourses:
          final result = await client.bykcChosenCourses();
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.courseName,
                  subtitle: item.courseTeacher,
                  fields: _compactFields(<FeatureField?>[
                    _field('课程 ID', item.courseId.toString()),
                    _field('地点', item.coursePosition),
                    _field('开始', item.courseStartDate),
                    _field('结束', item.courseEndDate),
                    _field('签到状态', '${item.checkin}'),
                    _field('成绩', item.score?.toString()),
                    _field(
                      '通过',
                      item.pass == null
                          ? null
                          : item.pass! > 0
                          ? '是'
                          : '否',
                    ),
                    _field('可签到', item.canSign ? '是' : '否'),
                    _field('可签退', item.canSignOut ? '是' : '否'),
                    _field(
                      '签到时间',
                      _timeWindow(
                        item.signConfig?.signStartDate,
                        item.signConfig?.signEndDate,
                      ),
                    ),
                    _field(
                      '签退时间',
                      _timeWindow(
                        item.signConfig?.signOutStartDate,
                        item.signConfig?.signOutEndDate,
                      ),
                    ),
                    _field('位置要求', _locationRequirement(item.signConfig)),
                    _field('签到类型', item.courseSignType?.toString()),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            details.length,
            '门已选博雅课程',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.bykcStatistics:
          final result = await client.bykcStatistics();
          final details = result.data.categories
              .map(
                (item) => FeatureDetail(
                  title: item.categoryName ?? item.subCategoryName ?? '分类',
                  subtitle: item.subCategoryName,
                  fields: _compactFields(<FeatureField?>[
                    _field('要求数量', item.requiredCount?.toString()),
                    _field('通过数量', item.passedCount?.toString()),
                    _field(
                      '达标',
                      item.qualified == null
                          ? null
                          : item.qualified!
                          ? '是'
                          : '否',
                    ),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            details.length,
            result.data.totalValidCount == null
                ? '博雅修读统计'
                : '有效课程 ${result.data.totalValidCount}',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    default:
      throw StateError('unexpected feature: $feature');
  }
}

ActionEligibility _toBykcActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

String? _timeWindow(String? start, String? end) {
  final normalizedStart = start?.trim();
  final normalizedEnd = end?.trim();
  if (normalizedStart == null || normalizedStart.isEmpty) return null;
  if (normalizedEnd == null || normalizedEnd.isEmpty) return normalizedStart;
  return '$normalizedStart–$normalizedEnd';
}

String? _locationRequirement(BridgeBykcSignConfig? config) {
  if (config == null) return null;
  if (config.signPoints.isEmpty) return '无需定位';
  return '指定位置（${config.signPoints.length} 处）';
}
