import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/mapping.dart' show bridgeCompactFields, bridgeField;
part 'timeline_projection.dart';

FeatureDetail bridgeTodayDetail(BridgeTodayClass item) => FeatureDetail(
  title: item.bizName,
  subtitle: item.shortName,
  presentation: TodayCoursePresentation(time: item.time, place: item.place),
  fields: bridgeCompactFields(<FeatureField?>[
    bridgeField('时间', item.time),
    bridgeField('地点', item.place),
  ]),
);
