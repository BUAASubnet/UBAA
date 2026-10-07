import 'package:ubaa_domain/ubaa_domain.dart';

bool uiCanReserveSeat(LibbookReserveAction? action) =>
    action?.eligibility == ActionEligibility.allowed &&
    [
      action!.areaId,
      action.seatId,
      action.day,
      action.segment,
      action.startTime,
      action.endTime,
    ].every((v) => v.trim().isNotEmpty);
