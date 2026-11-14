<script setup>
// 下载页顶部的平台入口；点击跳到对应平台的下载与安装说明。
const platforms = [
  { id: "android", name: "Android", detail: "APK · Android 7.0+", ready: true },
  { id: "windows", name: "Windows", detail: "EXE · Windows 10 / 11", ready: true },
  { id: "macos", name: "macOS", detail: "DMG · macOS 12+", ready: true },
  { id: "linux", name: "Linux", detail: "tar.gz · x64 / ARM64", ready: true },
  { id: "ios", name: "iOS", detail: "App Store", ready: false },
  { id: "ohos", name: "HarmonyOS", detail: "AppGallery", ready: false },
];
</script>

<template>
  <nav class="platform-grid" aria-label="选择平台">
    <a v-for="platform in platforms" :key="platform.id" :href="`#${platform.id}`">
      <strong>{{ platform.name }}</strong>
      <span>{{ platform.detail }}</span>
      <em :class="{ soon: !platform.ready }">{{ platform.ready ? "可下载" : "即将上架" }}</em>
    </a>
  </nav>
</template>

<style scoped>
.platform-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(9.5rem, 1fr));
  gap: 0.75rem;
  margin: 1.5rem 0;
}

.platform-grid a {
  display: grid;
  gap: 0.25rem;
  padding: 0.875rem 1rem;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  background: var(--vp-c-bg-soft);
  color: var(--vp-c-text-1);
  text-decoration: none;
  transition: border-color 0.2s;
}

.platform-grid a:hover {
  border-color: var(--vp-c-brand-1);
}

span {
  color: var(--vp-c-text-2);
  font-size: 0.8125rem;
}

em {
  justify-self: start;
  margin-top: 0.25rem;
  padding: 0 0.5rem;
  border-radius: 999px;
  background: var(--vp-c-brand-soft);
  color: var(--vp-c-brand-1);
  font-size: 0.75rem;
  font-style: normal;
  font-weight: 600;
  line-height: 1.6rem;
}

em.soon {
  background: var(--vp-c-default-soft);
  color: var(--vp-c-text-2);
}
</style>
