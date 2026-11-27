<script setup>
import { inject } from "vue";
const release = inject("release");
const loading = inject("releaseLoading");
const available = (platform) => platform.store || Boolean(release.value?.platforms[platform.id]?.length);
// 下载页顶部的平台入口；点击跳到对应平台的下载与安装说明。
const platforms = [
  { id: "android", name: "Android", detail: "APK · Android 7.0+" },
  { id: "windows", name: "Windows", detail: "EXE · Windows 10 / 11" },
  { id: "macos", name: "macOS", detail: "DMG · macOS 12+" },
  { id: "linux", name: "Linux", detail: "tar.gz · x64 / ARM64" },
  { id: "ios", name: "iOS", detail: "App Store", store: true },
  { id: "ohos", name: "HarmonyOS", detail: "AppGallery", store: true },
];
</script>

<template>
  <nav class="platform-grid" aria-label="选择平台">
    <a v-for="platform in platforms" :key="platform.id" :href="`#${platform.id}`">
      <strong>{{ platform.name }}</strong>
      <span>{{ platform.detail }}</span>
      <em :class="{ soon: !available(platform) }">{{ available(platform) ? "可下载" : loading ? "加载中" : "暂不可用" }}</em>
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
  grid-template-rows: auto 1fr auto;
  align-items: start;
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
