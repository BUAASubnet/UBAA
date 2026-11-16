import { onMounted, ref } from "vue";

// 同一页面会话中的首页与下载页共用清单，刷新失败时保留已显示的下载入口。
const release = ref(null);
const loading = ref(true);
let expiresAt = 0;
let pending;

async function refresh() {
  if (release.value && Date.now() < expiresAt) return;
  if (pending) return pending;
  loading.value = true;
  pending = (async () => {
    try {
      const response = await fetch("/release-data.json");
      if (response.ok) {
        release.value = await response.json();
        expiresAt = Date.now() + 60_000;
      }
    } catch { /* 请求失败时保留已有清单，下一次进入页面时重试。 */ }
    finally {
      loading.value = false;
      pending = undefined;
    }
  })();
  return pending;
}

export function useRelease() {
  onMounted(refresh);
  return { release, loading };
}
