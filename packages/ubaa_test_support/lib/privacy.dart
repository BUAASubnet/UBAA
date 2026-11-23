import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

const acceptedPrivacyVersionKey =
    'flutter.ubaa.preferences.accepted_privacy_version';

PreferenceValues acceptedPrivacyPreferences() => MemoryPreferenceValues()
  ..write(acceptedPrivacyVersionKey, bundledPrivacyPolicy.version.toString());

Future<String?> acceptedPrivacyVersion(String key) async =>
    key == acceptedPrivacyVersionKey
    ? bundledPrivacyPolicy.version.toString()
    : null;
