<script setup>
import { onMounted, onBeforeUnmount, ref, watch } from 'vue'
import { useData } from 'vitepress'
import 'artalk/Artalk.css'
import { prepareGuest } from './comment_identity.js'

const container = ref(null)
const failed = ref(false)
const management = ref(false)
const { isDark } = useData()
let comments
let disposed = false

async function load() {
  failed.value = false
  try {
    const { default: Artalk } = await import('artalk')
    if (disposed) return
    management.value = new URLSearchParams(location.search).get('manage') === '1'
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
      beforeSubmit: (editor, next) => {
        if (!management.value) prepareGuest(comments.ctx.getUser(), localStorage)
        next()
      },
    })
    if (!management.value) {
      prepareGuest(comments.ctx.getUser(), localStorage)
      const fields = comments.ctx.editor.getHeaderInputEls()
      fields.email.value = comments.ctx.getUser().getData().email
      fields.link.value = ''
    }
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
  <section aria-label="留言区" class="community-comments" :class="{ 'guest-comments': !management }">
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
.guest-comments :deep(.atk-header input[name="email"]),
.guest-comments :deep(.atk-header input[name="link"]) {
  display: none;
}
button {
  color: var(--vp-c-brand-1);
  text-decoration: underline;
}
</style>
