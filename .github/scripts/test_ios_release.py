"""验证发布版本规则，以及错误签名材料会在构建前被拒绝。"""

import copy
import hashlib
import unittest
from datetime import datetime, timezone

from ios_release import build_number, export_options, release_metadata, signing_metadata


class ReleaseMetadataTests(unittest.TestCase):
    def test_build_number_increases_for_new_runs_and_retries(self):
        self.assertEqual(build_number("30", "41", "1"), "71.1")
        self.assertEqual(build_number("30", "41", "2"), "71.2")
        self.assertEqual(build_number("30", "42", "1"), "72.1")

    def test_manual_build_number_and_apple_limits(self):
        self.assertEqual(build_number("30", "41", "1", " 9999.99.99 "), "9999.99.99")
        for value in ("0", "01", "10000", "1.100", "1.1.100", "1.2.3.4", "1.0-beta", "1\nIOS_VERSION=9"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                build_number("30", "41", "1", value)
        with self.assertRaises(ValueError):
            build_number("30", "9970", "1")

    def test_release_tag_must_match_source_version(self):
        properties = {"project.version": "1.8.0", "project.version.code": "30"}
        for tag in ("", "v1.8.0", "1.8.0"):
            self.assertEqual(release_metadata(properties, "41", "1", release_tag=tag)["IOS_VERSION"], "1.8.0")
        with self.assertRaises(ValueError):
            release_metadata(properties, "41", "1", release_tag="v1.7.6")
        with self.assertRaises(ValueError):
            release_metadata({**properties, "project.version": "1.8.0-beta"}, "41", "1")


class SigningMetadataTests(unittest.TestCase):
    def setUp(self):
        self.fingerprint = hashlib.sha1("测试证书".encode()).hexdigest().upper()
        self.identities = f'  1) {self.fingerprint} "Apple Distribution: 示例 (TEAM123456)"\n'
        self.profile = {
            "UUID": "12345678-1234-1234-1234-123456789abc",
            "TeamIdentifier": ["TEAM123456"],
            "ApplicationIdentifierPrefix": ["PREFIX1234"],
            "ExpirationDate": datetime(2027, 1, 1),
            "Entitlements": {"application-identifier": "PREFIX1234.cn.edu.ubaa", "get-task-allow": False},
            "DeveloperCertificates": ["测试证书".encode()],
        }
        self.now = datetime(2026, 9, 14, tzinfo=timezone.utc)

    def validate(self, profile=None, identities=None):
        return signing_metadata(profile or self.profile, identities or self.identities, "cn.edu.ubaa", "TEAM123456", self.now)

    def test_export_uses_matching_certificate_and_keeps_build_number(self):
        metadata = self.validate()
        options = export_options(metadata, "cn.edu.ubaa", "TEAM123456")
        self.assertEqual(options["signingCertificate"], self.fingerprint)
        self.assertEqual(options["provisioningProfiles"], {"cn.edu.ubaa": self.profile["UUID"]})
        self.assertFalse(options["manageAppVersionAndBuildNumber"])

    def test_rejects_expired_wrong_team_and_wrong_app_profiles(self):
        for key, value in (("ExpirationDate", datetime(2026, 1, 1)), ("TeamIdentifier", ["OTHER12345"]), ("UUID", "../profile")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate({**self.profile, key: value})
        for app_id in ("PREFIX1234.*", "PREFIX1234.cn.edu.other"):
            profile = copy.deepcopy(self.profile)
            profile["Entitlements"]["application-identifier"] = app_id
            with self.subTest(app_id=app_id), self.assertRaises(ValueError):
                self.validate(profile)

    def test_rejects_development_ad_hoc_and_enterprise_profiles(self):
        development = copy.deepcopy(self.profile)
        development["Entitlements"]["get-task-allow"] = True
        for profile in (development, {**self.profile, "ProvisionedDevices": ["测试设备"]}, {**self.profile, "ProvisionsAllDevices": True}):
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                self.validate(profile)

    def test_rejects_revoked_missing_or_unrelated_signing_identity(self):
        for identities in (
            self.identities.rstrip() + " (CSSMERR_TP_CERT_REVOKED)\n",
            "0 valid identities found",
            self.identities.replace(self.fingerprint, "A" * 40),
            self.identities.replace("Apple Distribution:", "Apple Development:"),
        ):
            with self.subTest(identities=identities), self.assertRaises(ValueError):
                self.validate(identities=identities)


if __name__ == "__main__":
    unittest.main()
