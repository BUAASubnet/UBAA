---
title: 交流与建议
description: 分享 UBAA 使用经验、反馈问题，或者提出你希望增加的功能，无需注册账号。
outline: false
---

# 交流与建议

想让 UBAA 帮你做什么？欢迎留下功能建议、反馈使用问题，也可以回复其他同学，分享自己的用法。

填写昵称和邮箱即可留言，无需注册账号，邮箱不会公开。反馈问题时，请附上应用版本、设备系统和操作步骤。提出功能建议时，可以说说你遇到了什么麻烦，以及希望怎样处理。

::: tip 公开留言
留言内容和昵称会公开展示。请勿填写学号、密码、验证码、联系方式等个人信息，截图中的个人信息也请先遮盖。维护者会清理垃圾留言和不当内容。
:::

<script setup>
import CommunityComments from './components/CommunityComments.vue'
</script>

<ClientOnly>
  <CommunityComments />
  <template #fallback><p>正在加载留言区……</p></template>
</ClientOnly>

<noscript>留言区需要启用 JavaScript。</noscript>

## 留言数据

留言服务由 UBAA 自行托管。服务器保存昵称、邮箱、留言、提交时间、浏览器信息和 IP 地址，用于展示讨论及限制垃圾留言。邮箱用于识别留言者，不公开展示，目前不发送邮件通知。浏览器会记住填写的信息，方便再次留言。

如需删除留言，请通过[联系维护者](/tech/privacy-policy#联系维护者)提供留言链接申请处理。
