import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/telemetry.dart';

AppServiceView bridgeAppServiceView(BridgeAppServiceState state) =>
    AppServiceView(
      available: state.available,
      telemetryAllowed: state.telemetryAllowed,
      consent: switch (state.consent) {
        BridgeAppServiceConsent.unasked => AppServiceConsent.unasked,
        BridgeAppServiceConsent.agreed => AppServiceConsent.agreed,
        BridgeAppServiceConsent.reconsentRequired =>
          AppServiceConsent.reconsentRequired,
        BridgeAppServiceConsent.basic => AppServiceConsent.basic,
      },
      policyVersion: state.policyVersion,
      agreedPolicyVersion: state.agreedPolicyVersion,
      telemetryEnabled: state.telemetryEnabled,
      canErase: state.canErase,
      erase: state.erasePending
          ? AppServiceEraseStatus.pending
          : AppServiceEraseStatus.idle,
      update: state.update == null ? null : _updateView(state.update!),
      announcements: List.unmodifiable(state.announcements.map(_announcement)),
    );

AppUpdateView _updateView(BridgeAppUpdate update) => AppUpdateView(
  status: switch (update.status) {
    BridgeAppUpdateStatus.upToDate => AppUpdateStatus.upToDate,
    BridgeAppUpdateStatus.updateAvailable => AppUpdateStatus.updateAvailable,
    BridgeAppUpdateStatus.updateRequired => AppUpdateStatus.updateRequired,
    BridgeAppUpdateStatus.unknown => AppUpdateStatus.unknown,
  },
  latestVersion: update.latestVersion,
  minSupportedVersion: update.minSupportedVersion,
  url: _httpsUrl(update.url),
  releaseNotes: update.releaseNotes,
  gateActive: update.gateActive,
  availableDismissed: update.availableDismissed,
);

AppAnnouncement _announcement(BridgeAppAnnouncement item) => AppAnnouncement(
  id: item.id,
  level: switch (item.level) {
    BridgeAppAnnouncementLevel.popup => AppAnnouncementLevel.popup,
    BridgeAppAnnouncementLevel.banner => AppAnnouncementLevel.banner,
  },
  title: item.title,
  body: item.body,
  linkUrl: _httpsUrl(item.linkUrl),
  linkText: item.linkText,
  confirmText: item.confirmText,
  startsAt: DateTime.parse(item.startsAt),
  endsAt: item.endsAt == null ? null : DateTime.parse(item.endsAt!),
);

Uri? _httpsUrl(String? value) {
  if (value == null) return null;
  final url = Uri.tryParse(value);
  return url != null && url.isScheme('https') && url.host.isNotEmpty
      ? url
      : null;
}

AppServiceEraseOutcome bridgeAppServiceErase(
  BridgeAppServiceEraseOutcome outcome,
) => switch (outcome) {
  BridgeAppServiceEraseOutcome.succeeded => AppServiceEraseOutcome.succeeded,
  BridgeAppServiceEraseOutcome.pending => AppServiceEraseOutcome.pending,
  BridgeAppServiceEraseOutcome.unavailable =>
    AppServiceEraseOutcome.unavailable,
};

final _counters = _wireNames(BridgeTelemetryCounter.values);
final _errors = _wireNames(BridgeTelemetryError.values);
final _timings = _wireNames(BridgeTelemetryTiming.values);
final _features = _wireNames(BridgeTelemetryFeature.values);
final _routes = _wireNames(BridgeTelemetryRoute.values);
final _results = _wireNames(BridgeTelemetryResult.values);
final _kinds = _wireNames(BridgeErrorKind.values);
final _buckets = {
  for (final bucket in BridgeTelemetryBucket.values)
    '${bucket.name.substring(0, 2)}_${bucket.name.substring(2)}': bucket,
};

Map<String, E> _wireNames<E extends Enum>(List<E> values) => {
  for (final value in values)
    value.name.replaceAllMapped(
      RegExp('[A-Z]'),
      (part) => '_${part[0]!.toLowerCase()}',
    ): value,
};

Future<void> bridgeRecordAppService(
  BridgeAppService service,
  TelemetryRecord record,
) async {
  final fields = record.properties;
  final feature = _features[fields['feature'] ?? 'app'];
  final route = _routes[fields['route'] ?? 'none'];
  if (feature == null || route == null) return;
  if (_counters[record.name] case final event?) {
    final result = _results[fields['result'] ?? 'success'];
    if (result == null) return;
    await service.enqueueCounter(
      event: event,
      feature: feature,
      route: route,
      result: result,
    );
  } else if (_errors[record.name] case final event?) {
    final kind = _kinds[fields['error_kind']];
    final code = fields['error_code'];
    final retryable = fields['retryable'];
    if (kind == null || code is! String || retryable is! bool) return;
    await service.enqueueError(
      event: event,
      feature: feature,
      route: route,
      errorCode: code,
      errorKind: kind,
      retryable: retryable,
      source: fields['source'] as String?,
    );
  } else if (_timings[record.name] case final metric?) {
    final bucket = _buckets[fields['bucket']];
    if (bucket == null) return;
    await service.enqueueTiming(
      metric: metric,
      feature: feature,
      route: route,
      bucket: bucket,
    );
  }
}
