<script setup>
import { data } from "../download.data.js";

const files = [...Object.values(data.platforms).flat(), data.licenses];
</script>

<template>
  <dl class="checksums">
    <template v-for="file in files" :key="file.name">
      <dt>{{ file.name }}</dt>
      <dd><code>{{ file.sha256 }}</code></dd>
    </template>
  </dl>
</template>

<style scoped>
.checksums {
  margin: 1rem 0;
  font-size: 0.875rem;
}

dt {
  margin-top: 0.75rem;
  font-weight: 600;
}

dd {
  margin: 0.25rem 0 0;
}

code {
  word-break: break-all;
}
</style>
