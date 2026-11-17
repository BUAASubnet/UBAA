<script setup>
import { onMounted, onBeforeUnmount, ref, watch } from 'vue'
import { useData } from 'vitepress'
import 'artalk/Artalk.css'

const container = ref(null)
const failed = ref(false)
const { isDark } = useData()
let comments
let disposed = false

async function load() {
  failed.value = false
  try {
    const { default: Artalk } = await import('artalk')
    if (disposed) return
    comments = Artalk.init({
      el: container.value,
      server: 'https://www.ubaa.top/comments-api/',
      site: 'UBAA',
      pageKey: '/community',
      pageTitle: '交流与建议',
      locale: 'zh-CN',
      darkMode: isDark.value,
      placeholder: '分享使用经验，或说说你希望增加的功能……',
      noComment: '还没有留言，来聊聊你的想法吧。',
      sendBtn: '发布留言',
      emoticons: false,
      imgUpload: false,
      avatarURLBuilder: () => '/favicon.png',
    })
  } catch {
    failed.value = true
  }
}

watch(isDark, (value) => comments?.setDarkMode(value))
onMounted(load)
onBeforeUnmount(() => {
  disposed = true
  comments?.destroy()
})
</script>

<template>
  <section aria-label="留言区" class="community-comments">
    <p v-if="failed" role="alert">
      留言区暂时无法加载。<button type="button" @click="load">重新加载</button>
    </p>
    <div ref="container" />
  </section>
</template>

<style scoped>
.community-comments {
  margin: 28px 0;
  --at-color-main: var(--vp-c-brand-1);
  --at-color-bg: var(--vp-c-bg);
}
button {
  color: var(--vp-c-brand-1);
  text-decoration: underline;
}
</style>
