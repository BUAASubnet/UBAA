<script setup>
import { computed, onMounted, ref } from "vue";
import { data } from "./announcements.data.js";
import { isCurrentAnnouncement } from "./announcement_time.js";

const props = defineProps({ history: Boolean });
const now = ref(data.builtAt);
onMounted(() => {
  now.value = Date.now();
});
const announcements = computed(() =>
  props.history
    ? data.announcements
    : data.announcements.filter((announcement) =>
        isCurrentAnnouncement(announcement, now.value),
      ),
);
const date = new Intl.DateTimeFormat("zh-CN", {
  dateStyle: "long",
  timeZone: "Asia/Shanghai",
});
</script>

<template>
  <p v-if="announcements.length === 0">
    {{ history ? "暂无历史公告。" : "当前没有有效公告。" }}
  </p>
  <article v-for="announcement in announcements" :key="announcement.id">
    <h2 :id="announcement.id">{{ announcement.title }}</h2>
    <p>
      <time :datetime="announcement.starts_at">{{
        date.format(new Date(announcement.starts_at))
      }}</time>
    </p>
    <p
      v-for="(paragraph, index) in announcement.body.split(/\n\s*\n/)"
      :key="index"
    >
      {{ paragraph }}
    </p>
    <p v-if="announcement.link_url">
      <a :href="announcement.link_url" target="_blank" rel="noreferrer">
        {{ announcement.link_text || "查看详情" }}
      </a>
    </p>
  </article>
</template>
