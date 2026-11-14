<script setup>
import { inject } from "vue";
import { data } from "../download.data.js";

const useBhpan = inject("useBhpan", true);
const props = defineProps({ platform: { type: String, required: true } });
const rows = data.platforms[props.platform];
</script>

<template>
  <ul class="download-options">
    <li v-for="row in rows" :key="row.name">
      <div class="info">
        <strong>{{ row.label }}</strong>
        <span>{{ row.hint }}</span>
      </div>
      <a class="download-button" :href="useBhpan ? row.url : row.mirrorUrl" data-no-router>
        下载 {{ row.type }}
        <small>{{ row.size }}</small>
      </a>
    </li>
  </ul>
</template>

<style scoped>
.download-options {
  margin: 1rem 0;
  padding: 0;
  list-style: none;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  overflow: hidden;
}

.download-options li {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin: 0;
  padding: 0.875rem 1rem;
}

.download-options li + li {
  border-top: 1px solid var(--vp-c-divider);
}

.info {
  display: grid;
  gap: 0.125rem;
  min-width: 0;
}

.info span {
  color: var(--vp-c-text-2);
  font-size: 0.8125rem;
  line-height: 1.5;
}

.download-button {
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  flex-shrink: 0;
  padding: 0.375rem 1rem;
  border-radius: 10px;
  background: var(--vp-button-brand-bg);
  color: var(--vp-button-brand-text);
  font-weight: 600;
  line-height: 1.3;
  text-decoration: none;
  white-space: nowrap;
}

.download-button small {
  font-size: 0.75rem;
  font-weight: 400;
  opacity: 0.85;
}

.download-button:hover {
  background: var(--vp-button-brand-hover-bg);
  color: var(--vp-button-brand-hover-text);
}
</style>
