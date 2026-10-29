# 安全策略

不得提交密码、Cookie、Token、Authorization 头、验证码图片、原始认证响应或完整个人资料。凭据文件、运行时材料和冻结参考始终遵守 [AGENTS 安全边界](AGENTS.md#安全边界)。

CLI 必须通过不回显的终端输入或标准输入读取密码，绝不接受明文密码参数。会话文件只包含 Cookie、连接模式和非秘密时间戳，并限制当前用户访问。产品中的必要个人字段显示按合同遮盖，共享日志、诊断和非业务输出还必须遵守[统一日志脱敏规则](docs/development/conventions.md#日志与诊断脱敏)。

必须校验 TLS 证书。

发现漏洞后，请登录 GitHub，通过本仓库的[私有漏洞报告](https://github.com/BUAASubnet/UBAA/security/advisories/new)联系维护者。仓库已启用此渠道。报告应包含受影响版本、复现条件、影响范围和脱敏后的最小步骤。不要附带真实凭据、Cookie、Token、验证码、原始学校响应或个人资料。

后续修复与披露时间在私有报告中协商。请勿在公开 Issue、Discussion 或 PR 中发布尚未修复漏洞的敏感复现资料；渠道访问失败时，也不要转为公开上传。
