<script setup>
import { data } from "../download.data.js";

const props = defineProps({ platform: { type: String, required: true } });
const rows = data.platforms[props.platform];
</script>

<template>
  <table class="download-table">
    <thead>
      <tr>
        <th>设备</th>
        <th>下载</th>
        <th>大小</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="row in rows" :key="row.name">
        <td>
          <strong>{{ row.label }}</strong>
          <span class="hint">{{ row.hint }}</span>
        </td>
        <td>
          <a class="download-button" :href="row.url">下载 {{ row.type }}</a>
        </td>
        <td class="size">{{ row.size }}</td>
      </tr>
    </tbody>
  </table>
</template>

<style scoped>
.download-table {
  display: table;
  width: 100%;
}

.hint {
  display: block;
  color: var(--vp-c-text-2);
  font-size: 0.8125rem;
  line-height: 1.5;
}

.size {
  white-space: nowrap;
}

.download-button {
  display: inline-block;
  padding: 0.25rem 0.875rem;
  border-radius: 999px;
  background: var(--vp-button-brand-bg);
  color: var(--vp-button-brand-text);
  font-weight: 600;
  text-decoration: none;
  white-space: nowrap;
}

.download-button:hover {
  background: var(--vp-button-brand-hover-bg);
  color: var(--vp-button-brand-hover-text);
}
</style>
