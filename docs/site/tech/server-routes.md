# 服务端与请求入口

UBAA v2.0 的校园业务请求由设备上的 Rust Core 发起，通过直连或学校 WebVPN 到达学校系统。新版不提供旧版 `/api/v1/…` 中转服务，也不需要配置旧版服务器地址。

开发者通过 Rust facade 或 Flutter Bridge 使用业务能力，详见[公共 API](/tech/shared-api)。

文档站是独立的静态网站，由 GitHub Pages 托管，不接收学校账号、登录密码或校园业务请求。
