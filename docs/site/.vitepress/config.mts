import { defineConfig } from 'vitepress'

const base = `${(process.env.DOCS_BASE || '/').replace(/\/$/, '')}/`

export default defineConfig({
  title: 'UBAA',
  description: 'UBAA v2.0 使用指南与开发说明',
  lang: 'zh-CN',
  base,
  head: [['link', { rel: 'icon', type: 'image/png', href: `${base}favicon.png` }]],
  lastUpdated: true,
  cleanUrls: true,
  themeConfig: {
    skipToContentLabel: '跳转到正文',
    sidebarMenuLabel: '目录',
    returnToTopLabel: '返回顶部',
    darkModeSwitchLabel: '外观',
    lightModeSwitchTitle: '切换到浅色模式',
    darkModeSwitchTitle: '切换到深色模式',
    notFound: { code: '404', title: '页面不存在', quote: '请从首页或搜索查找所需内容。', linkLabel: '返回首页', linkText: '返回首页' },
    nav: [
      { text: '首页', link: '/' },
      { text: '开始使用', link: '/guide/start' },
      { text: '功能说明', link: '/features/' },
      { text: '技术文档', link: '/tech/architecture' },
      { text: '隐私政策', link: '/tech/privacy-policy' },
      { text: '免责声明', link: '/tech/disclaimer' },
      { text: '公告中心', link: '/announcements/' },
      { text: '更新日志', link: '/changelog/' },
    ],
    sidebar: {
      '/guide/': [{ text: '开始使用', items: [
        { text: '安装与首次登录', link: '/guide/start' },
        { text: '常见问题', link: '/tech/troubleshooting' },
      ] }],
      '/features/': [
        {
          text: '功能说明',
          items: [
            { text: '功能总览', link: '/features/' },
            { text: '登录与连接模式', link: '/features/auth-and-connection' },
            { text: 'iHome', link: '/features/ihome' },
            { text: '课表与考试', link: '/features/schedule-and-exam' },
            { text: '成绩查询', link: '/features/grades' },
            { text: '博雅课程', link: '/features/bykc' },
            { text: '空教室查询', link: '/features/classroom' },
            { text: 'SPOC 作业', link: '/features/spoc' },
            { text: '希冀作业', link: '/features/judge' },
            { text: '图书馆座位', link: '/features/libbook' },
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
      options: {
        locales: { root: { translations: {
          button: { buttonText: '搜索文档', buttonAriaLabel: '搜索文档' },
          modal: { displayDetails: '显示详细列表', resetButtonTitle: '清除搜索',
            backButtonTitle: '关闭搜索', noResultsText: '没有找到相关内容',
            footer: { selectText: '选择', navigateText: '切换', closeText: '关闭' },
          },
        } } },
      },
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/BUAASubnet/UBAA' },
    ],
    footer: {
      message: 'UBAA 文档由仓库源码生成与维护。本软件由学生开发者制作并维护，为第三方工具，与北京航空航天大学官方无任何利益关系。',
    },
  },
})
