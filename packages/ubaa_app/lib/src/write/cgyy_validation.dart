import 'package:ubaa_domain/ubaa_domain.dart';

import '../contracts/backend.dart';

/// 校验并规范化场馆预约输入。
///
/// AppController 与生产 BridgeBackend 共用这一边界，避免绕过 controller 时
/// 把不完整或彼此冲突的 typed action 降级为 primitive 请求。
CgyySubmitInput validateCgyySubmitInput(CgyySubmitInput input) {
  if (input.purposeType <= 0 ||
      input.joinerNum <= 0 ||
      input.phone.trim().isEmpty ||
      input.theme.trim().isEmpty ||
      input.activityContent.trim().isEmpty ||
      input.joiners.trim().isEmpty) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  final actions = _validateCgyyReserveActions(input.actions);
  return CgyySubmitInput(
    actions: actions,
    phone: input.phone.trim(),
    theme: input.theme.trim(),
    purposeType: input.purposeType,
    joinerNum: input.joinerNum,
    activityContent: input.activityContent.trim(),
    joiners: input.joiners.trim(),
    isPhilosophySocialSciences: input.isPhilosophySocialSciences,
    isOffSchoolJoiner: input.isOffSchoolJoiner,
  );
}

List<CgyyReserveAction> _validateCgyyReserveActions(
  List<CgyyReserveAction> actions,
) {
  if (actions.isEmpty || actions.length > 2) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  final normalized = actions
      .map(
        (action) => CgyyReserveAction(
          venueSiteId: action.venueSiteId,
          reservationDate: action.reservationDate.trim(),
          spaceId: action.spaceId,
          timeId: action.timeId,
          venueSpaceGroupId: action.venueSpaceGroupId,
          timeOrdinal: action.timeOrdinal,
          eligibility: action.eligibility,
        ),
      )
      .toList(growable: false);
  if (normalized.any(
    (action) =>
        action.eligibility != ActionEligibility.allowed ||
        action.venueSiteId <= 0 ||
        action.reservationDate.isEmpty ||
        action.spaceId <= 0 ||
        action.timeId <= 0 ||
        action.timeOrdinal < 0 ||
        (action.venueSpaceGroupId != null && action.venueSpaceGroupId! <= 0),
  )) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  final first = normalized.first;
  if (normalized.any(
    (action) =>
        action.venueSiteId != first.venueSiteId ||
        action.reservationDate != first.reservationDate ||
        action.spaceId != first.spaceId ||
        action.venueSpaceGroupId != first.venueSpaceGroupId,
  )) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  final timeIds = normalized.map((action) => action.timeId).toSet();
  final ordinals = normalized.map((action) => action.timeOrdinal).toSet();
  if (timeIds.length != normalized.length ||
      ordinals.length != normalized.length ||
      (normalized.length == 2 &&
          (normalized[0].timeOrdinal - normalized[1].timeOrdinal).abs() != 1)) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
  normalized.sort(
    (left, right) => left.timeOrdinal.compareTo(right.timeOrdinal),
  );
  return List<CgyyReserveAction>.unmodifiable(normalized);
}
