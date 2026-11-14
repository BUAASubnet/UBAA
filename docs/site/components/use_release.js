import { onMounted, ref } from "vue";

export function useRelease() {
  const release = ref(null);
  onMounted(async () => {
    try {
      const response = await fetch("/release-data.json", { cache: "no-store" });
      if (response.ok) release.value = await response.json();
    } catch { /* 发布信息暂时不可用时保持等待状态。 */ }
  });
  return release;
}
