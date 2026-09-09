import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/ubaa_app.dart';
import '../ui_schedule_old/backend.dart';

/// 周导航用明确合成学期/教学周，沿既有课表fake，不触及学校网络。
class ScheduleNavigationBackend extends ScheduleOldBackend {
  ScheduleNavigationBackend({super.state});
  final selections = <FeatureQuery>[];
  Completer<void>? weekGate;
  FeatureQueryView? failOptions;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature == FeatureId.schedule && query.view == failOptions) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    if (feature == FeatureId.schedule &&
        query.view == FeatureQueryView.scheduleTerms) {
      selections.add(query);
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '合成本学期',
            presentation: TermPresentation(
              code: '2026-2027-1',
              selected: state != 'no-current',
              index: 1,
            ),
          ),
          FeatureDetail(
            title: '合成上一学期',
            presentation: TermPresentation(
              code: '2025-2026-2',
              selected: state == 'ambiguous-term',
              index: 2,
            ),
          ),
        ],
      );
    }
    if (feature == FeatureId.schedule &&
        query.view == FeatureQueryView.scheduleWeeks) {
      selections.add(query);
      if (weekGate case final gate?) {
        await gate.future;
      }
      final term = query.term!;
      final numbers = state == 'gapped' ? [3, 7, 12] : [3, 4, 5];
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          for (final (index, i) in numbers.indexed)
            FeatureDetail(
              title: title('合成教学第$i周'),
              presentation: WeekPresentation(
                requestTerm: term,
                responseTerm: term,
                number: i,
                current:
                    !{'no-current', 'no-current-week'}.contains(state) &&
                    index == 1,
                startDate: term == '2025-2026-2'
                    ? '2025-03-${(3 + index * 7).toString().padLeft(2, '0')}'
                    : index == 1
                    ? '2026-09-07'
                    : index == 0
                    ? '2026-08-31'
                    : '2026-09-14',
                endDate: term == '2025-2026-2'
                    ? '2025-03-${(9 + index * 7).toString().padLeft(2, '0')}'
                    : index == 1
                    ? '2026-09-13'
                    : index == 0
                    ? '2026-09-06'
                    : '2026-09-20',
              ),
            ),
          if (state == 'duplicate-week')
            FeatureDetail(
              title: '重复编号周',
              presentation: WeekPresentation(
                requestTerm: term,
                responseTerm: term,
                number: 4,
                current: false,
                startDate: '未确定',
                endDate: '未确定',
              ),
            ),
        ],
      );
    }
    return super.loadFeatureQuery(feature, query);
  }
}
