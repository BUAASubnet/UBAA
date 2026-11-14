---
layout: home
title: UBAA
titleTemplate: 北航校园服务一站式助手
description: UBAA 把北航的课表、作业、考试、成绩、博雅、预约和云盘集中在一个应用里，支持手机、平板和电脑。
hero:
  name: UBAA
  text: 校园服务，集中处理
  tagline: 课表、作业、考试、成绩、预约和云盘集中在一处，手机、平板和电脑都能用。
  actions:
    - theme: brand
      text: 下载 UBAA
      link: /download
    - theme: alt
      text: 开始使用
      link: /guide/start
features:
  - title: 学习与日程
    details: 汇集课表、考试、SPOC 和希冀作业，添加自己的日程与待办，按教学周安排重复事项。
    link: /features/agenda
    linkText: 日程与待办
  - title: 校园生活
    details: 查询博雅课程、图书馆座位、研讨室与空教室，查看 iHome 诉求和财务收入。
    link: /features/
    linkText: 全部功能
  - title: 直连与 WebVPN
    details: 默认自动选择直连或学校 WebVPN，也可以手动固定其中一种。
    link: /features/auth-and-connection
    linkText: 登录与连接方式
  - title: 北航云盘
    details: 浏览和管理文件，上传下载、分享与回收站集中使用，按需开启日程同步。
    link: /features/bhpan
    linkText: 北航云盘
  - title: 本地缓存
    details: 已保存的内容可在离线时查看，预约与提交仍需联网确认。
    link: /tech/data-and-privacy
    linkText: 数据与隐私说明
  - title: 多平台与命令模式
    details: 适配手机、平板和桌面，桌面命令与应用共用账号、缓存和日程。
    link: /features/command
    linkText: 桌面命令模式
---

<script setup>
import { useRelease } from './components/use_release.js'
const release = useRelease()
</script>

::: info UBAA v2.0
Android、Windows、macOS 和 Linux 安装包可以直接[下载](/download)，iOS 与 HarmonyOS 版本将通过应用商店提供。用过旧版的同学请看 [v2.0 新变化](/guide/ubaa2)。
:::
