import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/mapping.dart'
    show
        bridgeCompactFields,
        bridgeCountResult,
        bridgeField,
        bridgePagination,
        bridgeRequiredQueryValue;
part 'cache_projection.dart';
part 'cached_models.dart';

ActionEligibility _toLibbookActionEligibility(
  BridgeActionEligibility eligibility,
) => switch (eligibility) {
  BridgeActionEligibility.allowed => ActionEligibility.allowed,
  BridgeActionEligibility.denied => ActionEligibility.denied,
  BridgeActionEligibility.unknown => ActionEligibility.unknown,
};

String _libbookEligibilityLabel(ActionEligibility eligibility) =>
    switch (eligibility) {
      ActionEligibility.allowed => '是',
      ActionEligibility.denied => '否',
      ActionEligibility.unknown => '未知',
    };
