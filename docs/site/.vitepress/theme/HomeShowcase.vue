<script setup>
import { withBase } from "vitepress";
</script>

<template>
  <section class="home-showcase">
    <a class="frame" :href="withBase('/features/screenshots')">
      <img
        :src="withBase('/images/showcase-1920.webp')"
        :srcset="`${withBase('/images/showcase-960.webp')} 960w, ${withBase('/images/showcase-1920.webp')} 1920w`"
        sizes="(min-width: 1280px) 1152px, 100vw"
        width="1920"
        height="1080"
        alt="UBAA 在平板上显示整周日程、在手机上显示今日课表和待办"
        fetchpriority="high"
        decoding="async"
      />
    </a>
    <p class="caption">
      <a :href="withBase('/features/screenshots')">查看手机、平板和桌面截图</a>
    </p>
  </section>
</template>

<style scoped>
.home-showcase {
  margin: 0 auto 48px;
  padding: 0 24px;
  max-width: 1200px;
}

@media (min-width: 640px) {
  .home-showcase {
    padding: 0 48px;
  }
}

@media (min-width: 960px) {
  .home-showcase {
    padding: 0 64px;
    max-width: 1280px;
  }
}

.frame {
  display: block;
  overflow: hidden;
  border-radius: 16px;
  box-shadow: var(--vp-shadow-3);
}

img {
  display: block;
  width: 100%;
  height: auto;
}

.caption {
  margin-top: 12px;
  text-align: center;
  font-size: 0.875rem;
}

.caption a {
  color: var(--vp-c-brand-1);
  font-weight: 500;
}
</style>
