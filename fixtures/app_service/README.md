# 应用服务合同样例

`telemetry.json`、`erase.json`、`bootstrap.json` 的 `cases` 按 `schema` 选择 [JSON Schema](../../docs/contracts/app-service.schema.json) 中的定义，`valid` 是对 `payload` 的预期。删除成功和遥测接受返回空的 HTTP 204，样例只保存有正文的响应。

- 完整遥测样例中的 `users[].key: null` 是测试标记。校验前用合成输入在内存中计算标识，不把标识写入样例或测试输出。`mutations` 复制 `caseIndex` 指定的样例，再用 `value` 替换或写入 `path` 指定的字段，结果都应被拒绝。`constraints` 覆盖正文的 UTF-8 字节数、校园年份和日期与版本组合等额外约束。
- 启动配置的 `effectiveStatus` 与 `acceptedAnnouncementIds` 分别记录客户端解析后的更新状态与保留的公告。顶层和 `update` 校验通过后，单条公告仍须独立校验。
- `version_order.json` 的 `order` 为 `-1`、`0` 或 `1`，分别表示 `left` 小于、等于或大于 `right`。客户端和 Worker 实现版本比较时共用此文件。
