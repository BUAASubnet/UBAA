# 安全策略

Do not submit passwords, cookies, tokens, authorization headers, captcha images, raw authentication responses, or complete personal records. `.env.local`, runtime state, live artifacts, and reference repositories are ignored by design.

CLI 必须通过不回显的终端输入或标准输入读取密码，绝不接受明文密码参数。会话文件只包含 Cookie、连接模式和非秘密时间戳，并限制当前用户访问。日志和普通输出必须遮盖手机号及证件号码。

必须校验 TLS 证书。请私下向仓库维护者报告漏洞，不要在公开 issue 中附带敏感复现资料。
