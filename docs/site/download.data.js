import { readFileSync } from "node:fs";

// 下载页展示的平台与架构；清单缺少其中任何文件、大小或地址时构建失败。
const PLATFORMS = {
  android: [
    ["android-arm64-v8a.apk", "ARM64（arm64-v8a）", "大多数手机和平板", "APK"],
    ["android-armeabi-v7a.apk", "ARMv7（armeabi-v7a）", "只支持 32 位应用的旧设备", "APK"],
    ["android-x86_64.apk", "x86_64", "x86 架构的设备或模拟器", "APK"],
  ],
  windows: [["windows-x64.exe", "x64（Intel / AMD）", "大多数 Windows 电脑", "EXE"]],
  macos: [
    ["macos-arm64.dmg", "Apple Silicon", "“关于本机”显示 M 系列芯片", "DMG"],
    ["macos-x86_64.dmg", "Intel", "“关于本机”显示 Intel 处理器", "DMG"],
  ],
  linux: [
    ["linux-x64.tar.gz", "x64（x86_64）", "uname -m 显示 x86_64", "tar.gz"],
    ["linux-arm64.tar.gz", "ARM64（aarch64）", "uname -m 显示 aarch64", "tar.gz"],
  ],
};

export function describe(manifest) {
  const { version, build } = manifest;
  const prefix = `https://r2.ubaa.top/releases/v${version}/${build}/`;
  const assets = new Map(manifest.assets.map((asset) => [asset.name, asset]));
  const pick = (name) => {
    const asset = assets.get(name);
    if (
      !asset ||
      !Number.isInteger(asset.size) ||
      asset.size <= 0 ||
      asset.url !== prefix + name
    ) {
      throw new Error(`download.json 中的 ${name} 缺失或不完整`);
    }
    return {
      name,
      url: asset.url,
      size: `${(asset.size / 1e6).toFixed(1)} MB`,
    };
  };
  const platforms = Object.fromEntries(
    Object.entries(PLATFORMS).map(([platform, rows]) => [
      platform,
      rows.map(([suffix, label, hint, type]) => ({
        ...pick(`UBAA-${version}-${suffix}`),
        label,
        hint,
        type,
      })),
    ]),
  );
  return { version, build, platforms, licenses: pick("licenses.zip") };
}

export default {
  watch: ["./download.json"],
  load([file]) {
    return describe(JSON.parse(readFileSync(file, "utf8")));
  },
};
