import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'UBAA Docs',
  description: 'UBAA 项目文档',
  lang: 'zh-CN',
  lastUpdated: true,
  cleanUrls: true,
  themeConfig: {
    nav: [
      { text: '首页', link: '/' },
      { text: '功能说明', link: '/features/' },
      { text: '技术文档', link: '/tech/architecture' },
      { text: '隐私政策', link: '/tech/privacy-policy' },
      { text: '免责声明', link: '/tech/disclaimer' },
      { text: '公告中心', link: '/announcements/' },
      { text: '更新日志', link: '/changelog/' },
    ],
    sidebar: {
      '/features/': [
        {
          text: '功能说明',
          items: [
            { text: '功能总览', link: '/features/' },
            { text: '登录与连接模式', link: '/features/auth-and-connection' },
            { text: '课表与考试', link: '/features/schedule-and-exam' },
            { text: '成绩查询', link: '/features/grades' },
            { text: '博雅课程', link: '/features/bykc' },
            { text: '空教室查询', link: '/features/classroom' },
            { text: 'SPOC 作业', link: '/features/spoc' },
            { text: '希冀作业', link: '/features/judge' },
            { text: '课程签到', link: '/features/signin' },
            { text: '研讨室预约', link: '/features/cgyy' },
            { text: '阳光打卡', link: '/features/ygdk' },
            { text: '自动评教', link: '/features/evaluation' },
          ],
        },
      ],
      '/tech/': [
        {
          text: '技术文档',
          items: [
            { text: '架构总览', link: '/tech/architecture' },
            { text: '模块职责', link: '/tech/modules' },
            { text: '共享 API 与契约', link: '/tech/shared-api' },
            { text: '连接模式', link: '/tech/connection-modes' },
            { text: '隐私政策', link: '/tech/privacy-policy' },
            { text: '免责声明', link: '/tech/disclaimer' },
            { text: '服务端路由', link: '/tech/server-routes' },
            { text: '状态与存储', link: '/tech/state-storage' },
            { text: '配置说明', link: '/tech/configuration' },
            { text: '测试与质量', link: '/tech/testing' },
            { text: '发布与部署', link: '/tech/release-deployment' },
            { text: '排障指南', link: '/tech/troubleshooting' },
          ],
        },
      ],
      '/announcements/': [
        {
          text: '公告',
          items: [
            { text: '公告中心', link: '/announcements/' },
            { text: '公告历史', link: '/announcements/history' },
          ],
        },
      ],
      '/changelog/': [
        {
          text: '更新日志',
          items: [
            { text: '更新日志', link: '/changelog/' },
          ],
        },
      ],
      '/': [
        {
          text: 'UBAA',
          items: [
            { text: '项目首页', link: '/' },
            { text: '功能总览', link: '/features/' },
            { text: '架构总览', link: '/tech/architecture' },
            { text: '隐私政策', link: '/tech/privacy-policy' },
            { text: '免责声明', link: '/tech/disclaimer' },
            { text: '发布与部署', link: '/tech/release-deployment' },
          ],
        },
      ],
    },
    outline: {
      label: '本页目录',
      level: [2, 3],
    },
    docFooter: {
      prev: '上一页',
      next: '下一页',
    },
    lastUpdated: {
      text: '最后更新',
      formatOptions: {
        dateStyle: 'short',
        timeStyle: 'short',
      },
    },
    search: {
      provider: 'local',
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/BUAASubnet/UBAA' },
    ],
    footer: {
      message: 'UBAA 文档由仓库源码生成与维护。本软件由学生开发者制作并维护，为第三方工具，与北京航空航天大学官方无任何利益关系。',
    },
  },
})
