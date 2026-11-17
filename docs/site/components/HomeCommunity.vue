<script setup>
import CommunityComments from './CommunityComments.vue'
</script>

<template>
  <section id="community" class="home-community" aria-labelledby="community-title">
    <div class="community-intro">
      <span class="community-label">一起改进 UBAA</span>
      <h2 id="community-title">留言与建议</h2>
      <p class="community-lead">想让 UBAA 帮你做什么？</p>
      <p>分享你的用法、反馈遇到的问题，或聊聊希望增加的功能。也欢迎回复其他同学，为喜欢的建议点赞。</p>
      <div class="community-note">
        <strong>只填昵称，即可参与</strong>
        <p>留言会公开展示，请勿留下学号、密码、验证码或联系方式。</p>
      </div>
      <a href="/community#留言数据">了解留言数据的使用方式 →</a>
    </div>
    <div class="community-panel">
      <ClientOnly>
        <CommunityComments />
        <template #fallback><p role="status">正在加载留言区……</p></template>
      </ClientOnly>
      <noscript>留言区需要启用 JavaScript。</noscript>
    </div>
  </section>
</template>

<style scoped>
.home-community {
  display: grid;
  grid-template-columns: minmax(220px, 1fr) minmax(0, 2.2fr);
  gap: 48px;
  margin-top: 64px;
  padding-top: 48px;
  border-top: 1px solid var(--vp-c-divider);
  scroll-margin-top: 96px;
}
.community-label {
  color: var(--vp-c-brand-1);
  font-size: 13px;
  font-weight: 600;
  letter-spacing: .08em;
}
.community-intro h2 {
  border: 0;
  margin: 12px 0 20px;
  padding: 0;
  font-size: 28px;
  line-height: 1.3;
}
.community-intro p {
  color: var(--vp-c-text-2);
  font-size: 14px;
  line-height: 1.8;
}
.community-intro .community-lead {
  color: var(--vp-c-text-1);
  font-size: 17px;
  font-weight: 500;
}
.community-note {
  margin: 24px 0 16px;
  padding: 16px;
  border-radius: 12px;
  background: var(--vp-c-bg-soft);
  font-size: 14px;
}
.community-note p { margin: 8px 0 0; }
.community-intro a { font-size: 13px; }
.community-panel {
  min-width: 0;
  padding: 24px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 16px;
  background: var(--vp-c-bg);
}
.community-panel :deep(.community-comments) { margin: 0; }
@media (max-width: 767px) {
  .home-community {
    grid-template-columns: minmax(0, 1fr);
    gap: 24px;
    margin-top: 40px;
    padding-top: 32px;
  }
  .community-intro h2 { font-size: 24px; }
  .community-note { margin: 16px 0 12px; }
  .community-panel { padding: 16px; }
}
</style>
