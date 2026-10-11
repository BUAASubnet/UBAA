import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import '../context.dart';
import '../features/bykc/projection.dart';
import '../features/libbook/projection.dart';
import '../features/signin/projection.dart';
import '../features/cgyy/reader.dart';
import '../support/mapping.dart';

Future<FeatureResult> bridgePinnedWriteReadback(
  BridgeContext backend,
  WriteOperation operation,
  ConnectionMode route,
  FeatureQuery? query,
) async {
  final pinned = bridgeToBridgeConnectionMode(route);
  try {
    switch (operation) {
      case WriteOperation.bykcSelectCourse:
      case WriteOperation.bykcDeselectCourse:
      case WriteOperation.bykcSignCourse:
        final result = await backend.client.bykcChosenCoursesOnRoute(
          route: pinned,
        );
        return bridgeProjectBykcChosen(
          result.data,
          bridgeToConnectionMode(result.pinnedRoute),
        );
      case WriteOperation.signinPerform:
        final result = await backend.client.signinTodayOnRoute(route: pinned);
        return bridgeMapSigninHome(
          result.data,
          const FeatureQuery(),
          bridgeToConnectionMode(result.pinnedRoute),
        );
      case WriteOperation.libbookReserve:
      case WriteOperation.libbookCancelBooking:
        final selected =
            query ?? const FeatureQuery(view: FeatureQueryView.libbookBookings);
        final result = await backend.client.libbookBookingsOnRoute(
          route: pinned,
          page: selected.page,
          limit: selected.size,
        );
        return bridgeProjectLibbookBookings(
          result.data,
          bridgeToConnectionMode(result.pinnedRoute),
          bridgeDateOnly(DateTime.now()),
          selected,
        );
      case WriteOperation.cgyySubmitReservation:
        return bridgeLoadCgyyOrdersOnRoute(
          backend,
          route: route,
          page: 1,
          size: 20,
        );
      default:
        throw const BackendException(UbaaErrorCode.invalidInput);
    }
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}
