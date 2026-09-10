/// 旧版关于页的两个公开目的地，不携带账号或学校业务参数。
enum AppLink {
  project('开源项目 (GitHub)', 'https://github.com/BUAASubnet/UBAA'),
  feedback('反馈建议 (Issues)', 'https://github.com/BUAASubnet/UBAA/issues');

  const AppLink(this.label, this.url);
  final String label;
  final String url;
}
