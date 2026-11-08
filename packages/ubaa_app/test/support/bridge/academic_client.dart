import 'package:ubaa_bindings/ubaa_bindings.dart';

BridgeRoutedGradeOverview fixtureUndergraduateOverview(
  BridgeRouteDecision route,
) => BridgeRoutedGradeOverview(
  data: const BridgeGradeOverview(
    graduate: false,
    grades: [],
    statistics: null,
    terms: [],
  ),
  route: route,
);
