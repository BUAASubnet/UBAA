import { defineConfig } from 'vitepress'

const base = `${(process.env.DOCS_BASE || '/').replace(/\/$/, '')}/`

export default defineConfig({
  title: 'UBAA',
  description: 'UBAA 使用指南：北航学生的一站式校园助手',
  lang: 'zh-CN',
  base,
  head: [['link', { rel: 'icon', type: 'image/png', href: `${base}favicon.png` }]],
  lastUpdated: true,
  cleanUrls: true,
  srcExclude: ['announcements/[0-9]*.md'],
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
      { text: '下载', link: '/download' },
      { text: '开始使用', link: '/guide/start' },
      { text: '新版变化', link: '/guide/ubaa2' },
      { text: '功能说明', link: '/features/' },
      { text: '帮助', link: '/tech/troubleshooting' },
      { text: '公告中心', link: '/announcements/' },
      { text: '更新日志', link: '/changelog/' },
    ],
    sidebar: {
      '/guide/': [{ text: '开始使用', items: [
        { text: '下载 UBAA', link: '/download' },
        { text: '安装与首次登录', link: '/guide/start' },
        { text: 'v2.0 的升级变化', link: '/guide/ubaa2' },
        { text: '常见问题', link: '/tech/troubleshooting' },
      ] }],
      '/features/': [
        {
          text: '开始',
          items: [
            { text: '功能总览', link: '/features/' },
            { text: '应用截图', link: '/features/screenshots' },
            { text: '登录与连接方式', link: '/features/auth-and-connection' },
          ],
        },
        {
          text: '首页与日程',
          items: [
            { text: '日程与待办', link: '/features/agenda' },
          ],
        },
        {
          text: '学习',
          items: [
            { text: '课表与考试', link: '/features/schedule-and-exam' },
            { text: '课堂签到', link: '/features/signin' },
            { text: 'SPOC 作业', link: '/features/spoc' },
            { text: '希冀作业', link: '/features/judge' },
            { text: '博雅课程', link: '/features/bykc' },
            { text: '成绩查询', link: '/features/grades' },
            { text: '教学评教', link: '/features/evaluation' },
          ],
        },
        {
          text: '校园',
          items: [
            { text: 'iHome', link: '/features/ihome' },
            { text: '北航云盘', link: '/features/bhpan' },
            { text: '财务查询', link: '/features/finance' },
            { text: '空教室查询', link: '/features/classroom' },
            { text: '图书馆座位', link: '/features/libbook' },
            { text: '研讨室预约', link: '/features/cgyy' },
            { text: '阳光打卡', link: '/features/ygdk' },
          ],
        },
        {
          text: '桌面',
          items: [
            { text: '桌面命令模式', link: '/features/command' },
          ],
        },
      ],
      '/tech/': [
        {
          text: '帮助',
          items: [
            { text: '常见问题', link: '/tech/troubleshooting' },
            { text: '设置说明', link: '/tech/configuration' },
            { text: '数据与隐私说明', link: '/tech/data-and-privacy' },
            { text: '隐私政策', link: '/tech/privacy-policy' },
            { text: '免责声明', link: '/tech/disclaimer' },
            { text: '参与开发', link: '/tech/contributing' },
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
            { text: '下载 UBAA', link: '/download' },
            { text: 'v2.0 的升级变化', link: '/guide/ubaa2' },
            { text: '功能总览', link: '/features/' },
            { text: '常见问题', link: '/tech/troubleshooting' },
            { text: '隐私政策', link: '/tech/privacy-policy' },
            { text: '免责声明', link: '/tech/disclaimer' },
            { text: '参与开发', link: '/tech/contributing' },
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
      message: '本软件由学生开发者制作并维护，为第三方工具，与北京航空航天大学官方无任何利益关系。',
    },
  },
})
