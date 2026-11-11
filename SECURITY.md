# 安全策略

## 报告漏洞

发现安全漏洞时，请登录 GitHub，通过本仓库的[私有漏洞报告](https://github.com/BUAASubnet/UBAA/security/advisories/new)联系维护者。

报告中请写明：

- 受影响的版本
- 复现条件和最少的复现步骤（请脱敏）
- 影响范围

请不要附带真实凭据、Cookie、Token、验证码、学校系统的原始响应或个人资料。修复和披露时间在私有报告中协商。

漏洞修复前，请不要在公开的 Issue、Discussion 或 PR 中发布复现资料。私有报告渠道无法访问时，也不要改为公开上传。

## 项目的安全承诺

- 校园请求必须校验 TLS 证书。
- 命令模式只通过不回显的终端输入或标准输入读取密码，不接受命令行参数中的明文密码。
- 会话文件只保存 Cookie、连接方式和不含秘密的时间戳，只允许当前系统用户访问。
- 产品中必要的个人字段按合同遮盖显示；日志和诊断输出遵守[日志与诊断脱敏](docs/development/conventions.md#日志与诊断脱敏)规则。
- 仓库不提交密码、Cookie、Token、Authorization 头、验证码图片、原始认证响应或完整个人资料。贡献者需要遵守的完整规则见 [AGENTS.md 安全边界](AGENTS.md#安全边界)。

用户数据如何处理，见[隐私政策](https://www.ubaa.top/tech/privacy-policy)。
