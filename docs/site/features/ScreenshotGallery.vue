<script setup>
import { withBase } from 'vitepress'

defineProps({ group: { type: String, required: true } })

const groups = {
  phone: {
    name: '手机版',
    width: 600,
    height: 1301,
    shots: [
      ['01_home', '首页', '查看当天的课程、常用功能和待办。'],
      ['02_schedule', '课表', '按周查看课程时间和上课地点。'],
      ['03_agenda', '日程', '把课程、作业截止时间和自建事项放在一起。'],
      ['04_grades', '成绩', '按学期查看课程成绩、学分和绩点。'],
      ['05_coursework', 'SPOC 作业', '按课程查看作业、截止时间和提交状态。'],
      ['06_exams', '考试', '查看考试时间、地点和座位。'],
    ],
  },
  tablet: {
    name: '平板版',
    width: 900,
    height: 675,
    shots: [
      ['01_home', '首页', '今日课表和待办左右并排。'],
      ['02_schedule', '课表', '侧栏和整周课表并排显示。'],
      ['03_agenda', '日程', '月历、事项筛选和周视图同屏显示。'],
      ['04_grades', '成绩', '同页查看学期统计和各门课程成绩。'],
      ['05_coursework', 'SPOC 作业', '按课程列出作业、截止时间和提交状态。'],
      ['06_exams', '考试', '即将到来和尚未安排的考试分开列出。'],
    ],
  },
  desktop: {
    name: '桌面版',
    width: 900,
    height: 563,
    shots: [
      ['01_home', '首页', '在宽屏上同时查看今日课表和待办。'],
      ['02_schedule', '课表', '整周课表一屏显示，标出当前时间。'],
      ['03_agenda', '日程', '在周历中查看上课、组会和作业截止时间。'],
    ],
  },
}
</script>

<template>
  <div class="gallery" :class="group">
    <figure v-for="[file, title, description] in groups[group].shots" :key="file">
      <a
        class="preview"
        :href="withBase(`/screenshots/${group}/${file}.png`)"
        :aria-label="`查看原图：${groups[group].name}${title}`"
      >
        <img
          :src="withBase(`/screenshots/${group}/${file}.webp`)"
          :alt="`UBAA ${groups[group].name}${title}截图`"
          :width="groups[group].width"
          :height="groups[group].height"
          loading="lazy"
          decoding="async"
        />
      </a>
      <figcaption>
        <strong>{{ title }}</strong>
        <span>{{ description }}</span>
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

.gallery.tablet,
.gallery.desktop {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 18rem), 1fr));
}

figure {
  width: min(100%, 25rem);
  margin: 0 auto;
}

.tablet figure,
.desktop figure {
  width: 100%;
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
</style>
