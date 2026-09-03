part of '../bridge_backend.dart';

Future<FeatureResult> _loadYgdkFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  final client = backend.client;
  switch (feature) {
    case FeatureId.ygdk:
      switch (query.view) {
        case FeatureQueryView.summary:
          final result = await client.ygdkOverview();
          final details = result.data.items
              .map(
                (item) => FeatureDetail(
                  title: item.name,
                  fields: _compactFields(<FeatureField?>[
                    _field('项目编号', '${item.itemId}'),
                    item.kind == null ? null : _field('类型', '${item.kind}'),
                  ]),
                ),
              )
              .toList(growable: false);
          final summary = result.data.summary.termTarget == null
              ? '已打卡 ${result.data.summary.termCount} 次'
              : '学期进度 ${result.data.summary.termCount}/${result.data.summary.termTarget}';
          return FeatureResult.success(
            summary: summary,
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.ygdkRecords:
          final page = query.page <= 0 ? 1 : query.page;
          final size = query.size.clamp(1, 100);
          final result = await client.ygdkRecords(page: page, size: size);
          final details = result.data.content
              .map(
                (item) => FeatureDetail(
                  title: item.itemName ?? '打卡记录 ${item.recordId}',
                  subtitle: item.createdAtLabel ?? item.createdAt,
                  fields: _compactFields(<FeatureField?>[
                    _field('记录编号', '${item.recordId}'),
                    _field('开始时间', item.startTime),
                    _field('结束时间', item.endTime),
                    _field('地点', item.place),
                    _field('公开状态', item.isOpen ? '公开' : '不公开'),
                    _field('图片数量', '${item.imageCount}'),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.content.length,
            '条打卡记录',
            details: details,
            pagination: _pagination(
              page: result.data.page,
              size: result.data.size,
              total: result.data.total,
              hasMore: result.data.hasMore,
            ),
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.libbookAreas:
        case FeatureQueryView.bykcDetail:
        case FeatureQueryView.bykcProfile:
        case FeatureQueryView.bykcChosenCourses:
        case FeatureQueryView.bykcStatistics:
        case FeatureQueryView.scheduleToday:
        case FeatureQueryView.scheduleTerms:
        case FeatureQueryView.scheduleWeeks:
        case FeatureQueryView.scheduleWeek:
        case FeatureQueryView.examArranged:
        case FeatureQueryView.examNotArranged:
        case FeatureQueryView.gradesScored:
        case FeatureQueryView.gradesMissing:
        case FeatureQueryView.evaluationPending:
        case FeatureQueryView.libbookAreaDetail:
        case FeatureQueryView.libbookSeats:
        case FeatureQueryView.libbookBookings:
        case FeatureQueryView.cgyyPurposeTypes:
        case FeatureQueryView.cgyyDayInfo:
        case FeatureQueryView.cgyyOrders:
        case FeatureQueryView.cgyyOrderDetail:
        case FeatureQueryView.cgyyLockCode:
        case FeatureQueryView.spocDetail:
        case FeatureQueryView.judgeDetail:
        case FeatureQueryView.judgeBatchDetails:
        case FeatureQueryView.signinPending:
        case FeatureQueryView.signinCompleted:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    default:
      throw StateError('unexpected feature: $feature');
  }
}
