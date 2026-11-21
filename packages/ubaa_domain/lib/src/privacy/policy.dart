/// 应用内离线显示的隐私政策内容。
enum PrivacyPolicyBlockKind { heading, paragraph, bullet }

final class PrivacyPolicyBlock {
  const PrivacyPolicyBlock({
    required this.kind,
    required this.level,
    required this.text,
    this.bold = const [],
  });

  final PrivacyPolicyBlockKind kind;

  /// 标题使用 Markdown 标题级别，段落和列表项为 0。
  final int level;
  final String text;

  /// 正文中需要加粗的 UTF-16 起止偏移，按显示顺序排列。
  final List<(int, int)> bold;
}

final class PrivacyPolicyDocument {
  const PrivacyPolicyDocument({
    required this.version,
    required this.title,
    required this.blocks,
    required this.changes,
  });

  final int version;
  final String title;
  final List<PrivacyPolicyBlock> blocks;
  final List<String> changes;
}
