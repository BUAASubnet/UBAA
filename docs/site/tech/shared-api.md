# 公共 API 与数据边界

Rust 宿主通过 `ubaa_core` 的 facade 使用业务能力。Flutter 通过 Bridge 使用相应的数据模型和操作接口，学校原始响应、Cookie、Token 与内部客户端不暴露给 UI。

读取返回结构化结果和稳定错误。写入先准备目标并核验资格，再由用户操作触发提交；可能已发送的请求不会因刷新失败而自动重发。

CLI 支持人类可读与 JSON 输出。调用方需要同时判断命令结果与具体业务结果，不能把进程正常退出一概视为提交成功。

字段、版本与退出码以仓库[公开合同](https://github.com/BUAASubnet/UBAA/tree/ubaa2/docs/contracts)为准。网站不复制完整 Schema，以免两份定义漂移。
