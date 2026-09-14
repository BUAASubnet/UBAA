"""生成 iOS 发布元数据，并验证 App Store 签名材料。"""

import hashlib
import os
import plistlib
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def build_number(version_code, run_number, run_attempt, override=""):
    value = override.strip() or f"{int(version_code) + int(run_number)}.{int(run_attempt)}"
    if not re.fullmatch(r"[1-9][0-9]{0,3}(?:\.[0-9]{1,2}){0,2}", value):
        raise ValueError("iOS 构建号必须为 1～3 段数字，首段最多 4 位且大于 0，其余段最多 2 位")
    return value


def release_metadata(properties, run_number, run_attempt, override="", release_tag=""):
    version = properties["project.version"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("project.version 必须采用 App Store 支持的三段版本号，例如 1.8.0")
    if release_tag and release_tag not in (version, f"v{version}"):
        raise ValueError("Release tag 与 gradle.properties 中的 project.version 不一致")
    number = build_number(properties["project.version.code"], run_number, run_attempt, override)
    return {"IOS_VERSION": version, "IOS_BUILD_NUMBER": number, "IOS_ASSET_NAME": f"UBAA-iOS-v{version}-{number}"}


def signing_metadata(profile, identities, bundle_id, team_id, now=None):
    now = now or datetime.now(timezone.utc)
    expiry = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
    if expiry <= now:
        raise ValueError("iOS 描述文件已过期，请更新 IOS_PROVISIONING_PROFILE_BASE64")
    entitlements = profile["Entitlements"]
    if team_id not in profile.get("TeamIdentifier", []):
        raise ValueError("iOS 描述文件的 Team ID 与 IOS_TEAM_ID 不一致")
    prefixes = profile.get("ApplicationIdentifierPrefix", [team_id])
    if entitlements.get("application-identifier") not in [f"{prefix}.{bundle_id}" for prefix in prefixes]:
        raise ValueError("iOS 描述文件的 App ID 与 IOS_BUNDLE_ID 不一致，且不能使用通配符")
    if entitlements.get("get-task-allow") or "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
        raise ValueError("必须使用 App Store Connect 分发描述文件，不能使用开发、Ad Hoc 或企业描述文件")
    profile_uuid = profile["UUID"]
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", profile_uuid):
        raise ValueError("iOS 描述文件的 UUID 格式错误")
    certificates = {hashlib.sha1(cert).hexdigest().upper() for cert in profile["DeveloperCertificates"]}
    # 仅接受可用的分发身份；带有撤销或过期错误后缀的身份不会匹配。
    for fingerprint, name in re.findall(r'^\s*\d+\)\s+([A-F0-9]{40})\s+"([^"]+)"\s*$', identities, re.MULTILINE):
        if fingerprint in certificates and name.startswith(("Apple Distribution:", "iPhone Distribution:")):
            return {"IOS_PROFILE_UUID": profile_uuid, "IOS_SIGNING_IDENTITY": fingerprint}
    raise ValueError("P12 中没有与描述文件匹配的有效 Apple Distribution 证书及私钥")


def export_options(metadata, bundle_id, team_id):
    return {
        "method": "app-store-connect",
        "destination": "export",
        "signingStyle": "manual",
        "teamID": team_id,
        "signingCertificate": metadata["IOS_SIGNING_IDENTITY"],
        "provisioningProfiles": {bundle_id: metadata["IOS_PROFILE_UUID"]},
        "manageAppVersionAndBuildNumber": False,
        "stripSwiftSymbols": True,
        "uploadSymbols": True,
    }


def emit(values):
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("metadata", "signing"):
        raise ValueError("用法：python3 .github/scripts/ios_release.py metadata|signing")
    if sys.argv[1] == "metadata":
        properties = {}
        for line in Path("gradle.properties").read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                key, value = line.split("=", 1)
                properties[key.strip()] = value.strip()
        metadata = release_metadata(
            properties,
            os.environ["GITHUB_RUN_NUMBER"],
            os.environ["GITHUB_RUN_ATTEMPT"],
            os.environ.get("IOS_BUILD_NUMBER_OVERRIDE", ""),
            os.environ.get("IOS_RELEASE_TAG", ""),
        )
        emit(metadata)
        print(f"iOS 发布版本：{metadata['IOS_VERSION']}，构建号：{metadata['IOS_BUILD_NUMBER']}")
    else:
        signing_dir = Path(os.environ["IOS_SIGNING_DIR"])
        bundle_id, team_id = os.environ["IOS_BUNDLE_ID"], os.environ["IOS_TEAM_ID"]
        profile = plistlib.loads((signing_dir / "profile.plist").read_bytes())
        identities = (signing_dir / "identities.txt").read_text(encoding="utf-8")
        metadata = signing_metadata(profile, identities, bundle_id, team_id)
        (signing_dir / "ExportOptions.plist").write_bytes(plistlib.dumps(export_options(metadata, bundle_id, team_id)))
        emit(metadata)
        print("App Store 分发描述文件、Bundle ID、Team ID 和签名身份校验通过。")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, plistlib.InvalidFileException) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
