<script setup>
import { withBase } from 'vitepress'

defineProps({ group: { type: String, required: true } })

const phone = [
  ['01_home', '首页', '查看当天的课程、常用功能和待办。'],
  ['02_schedule', '课表', '按周查看课程时间和上课地点。'],
  ['03_agenda', '日程', '把课程、作业截止时间和自建事项放在一起。'],
  ['04_grades', '成绩', '按学期查看课程成绩、学分和绩点。'],
  ['05_coursework', 'SPOC 作业', '按课程查看作业、截止时间和提交状态。'],
  ['06_exams', '考试', '查看考试时间、地点和座位。'],
].map(([file, title, description]) => ({
  file: `iphone/${file}.png`,
  title,
  description,
  width: 1320,
  height: 2868,
}))

const wide = [
  {
    file: 'ipad/01_home.png',
    title: 'iPad 首页',
    description: '从侧栏切换学习、日程和校园服务。',
    width: 2064,
    height: 2752,
  },
  {
    file: 'desktop/01_home.png',
    title: '桌面首页',
    description: '在同一窗口查看课程、快捷入口和待办。',
    width: 2880,
    height: 1800,
  },
]
</script>

<template>
  <div class="gallery" :class="{ wide: group === 'wide' }">
    <figure v-for="shot in group === 'wide' ? wide : phone" :key="shot.file">
      <a
        class="preview"
        :href="withBase(`/screenshots/${shot.file}`)"
        :aria-label="`查看原图：${shot.title}`"
      >
        <img
          :src="withBase(`/screenshots/${shot.file}`)"
          :alt="`UBAA ${shot.title}宣传图`"
          :width="shot.width"
          :height="shot.height"
          loading="lazy"
          decoding="async"
        />
      </a>
      <figcaption>
        <strong>{{ shot.title }}</strong>
        <span>{{ shot.description }}</span>
      </figcaption>
    </figure>
  </div>
</template>

<style scoped>
.gallery {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 13rem), 1fr));
  gap: 1.5rem;
  margin: 1.5rem 0;
}

.gallery.wide {
  grid-template-columns: minmax(0, 1fr) minmax(0, 1.65fr);
}

figure {
  width: min(100%, 25rem);
  margin: 0 auto;
}

.preview {
  display: block;
  overflow: hidden;
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
}

.preview:focus-visible {
  outline: 2px solid var(--vp-c-brand-1);
  outline-offset: 3px;
}

img {
  display: block;
  width: 100%;
  height: auto;
}

figcaption {
  display: grid;
  gap: 0.25rem;
  margin-top: 0.75rem;
}

figcaption span {
  color: var(--vp-c-text-2);
  font-size: 0.875rem;
  line-height: 1.5;
}

@media (max-width: 560px) {
  .gallery.wide {
    grid-template-columns: 1fr;
  }
}
</style>
