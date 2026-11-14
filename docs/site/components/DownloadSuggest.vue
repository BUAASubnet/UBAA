<script setup>
import { inject, onMounted, ref, watch } from "vue";
const release = inject("release");

// 服务端渲染时不知道访问设备，挂载后按浏览器信息推荐；识别不了就不显示。
const useBhpan = inject("useBhpan", true);
const suggestion = ref(null);


const NAMES = { android: "Android", windows: "Windows", macos: "macOS", linux: "Linux" };

async function architecture() {
  try {
    const values = await navigator.userAgentData?.getHighEntropyValues?.(["architecture"]);
    return values?.architecture ?? "";
  } catch {
    return "";
  }
}

async function detect() {
  if (!release.value) return null;
  const { android, windows, macos, linux } = release.value.platforms;
  const agent = navigator.userAgent;
  if (/OpenHarmony/i.test(agent)) return { store: "HarmonyOS", anchor: "#ohos" };
  if (/iPhone|iPad|iPod/.test(agent) || (/Macintosh/.test(agent) && navigator.maxTouchPoints > 1)) {
    return { store: "iOS", anchor: "#ios" };
  }
  if (/Android/.test(agent)) return { platform: "android", rows: [android[0]] };
  if (/Windows/.test(agent)) return { platform: "windows", rows: windows };
  const arch = await architecture();
  if (/Macintosh|Mac OS X/.test(agent)) {
    if (arch === "arm") return { platform: "macos", rows: [macos[0]] };
    if (arch === "x86") return { platform: "macos", rows: [macos[1]] };
    return { platform: "macos", rows: macos };
  }
  if (/Linux/.test(agent)) {
    if (arch === "arm" || /aarch64/.test(agent)) return { platform: "linux", rows: [linux[1]] };
    if (arch === "x86" || /x86_64/.test(agent)) return { platform: "linux", rows: [linux[0]] };
    return { platform: "linux", rows: linux };
  }
  return null;
}

watch(release, async () => { suggestion.value = await detect(); });
onMounted(async () => {
  suggestion.value = await detect();
});
</script>

<template>
  <div v-if="suggestion" class="download-suggest">
    <template v-if="suggestion.store">
      <p>
        看起来你在使用 {{ suggestion.store }} 设备。{{ suggestion.store }} 版将通过应用商店提供，
        <a :href="suggestion.anchor">查看说明</a>。
      </p>
    </template>
    <template v-else>
      <p>看起来你在使用 {{ NAMES[suggestion.platform] }} 设备，推荐下载：</p>
      <div class="actions">
        <a v-for="row in suggestion.rows" :key="row.name" class="primary" :href="useBhpan ? row.url : row.mirrorUrl" target="_self">
          下载 {{ NAMES[suggestion.platform] }} 版
          <small>{{ row.label }} · {{ row.size }}</small>
        </a>
      </div>
      <p class="note">
        不是这台设备？在下方选择其他平台或架构，安装说明见
        <a :href="`#${suggestion.platform}`">{{ NAMES[suggestion.platform] }}</a>。
      </p>
    </template>
  </div>
</template>

<style scoped>
.download-suggest {
  margin: 1.5rem 0;
  padding: 1rem 1.25rem;
  border: 1px solid var(--vp-c-brand-soft);
  border-radius: 12px;
  background: var(--vp-c-brand-soft);
}

.download-suggest p {
  margin: 0;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin: 0.75rem 0;
}

.primary {
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  padding: 0.5rem 1.25rem;
  border-radius: 12px;
  line-height: 1.4;
  background: var(--vp-button-brand-bg);
  color: var(--vp-button-brand-text);
  font-weight: 600;
  text-decoration: none;
}

.primary small {
  font-size: 0.75rem;
  font-weight: 400;
  opacity: 0.85;
}

.primary:hover {
  background: var(--vp-button-brand-hover-bg);
  color: var(--vp-button-brand-hover-text);
}

.note {
  color: var(--vp-c-text-2);
  font-size: 0.875rem;
}
</style>
