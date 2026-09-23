# P4-AG候选双路线只读复验

本页为阶段历史证据，不覆盖后续提交。候选：P4-AG `3ca371fc`，CLI JSON schema v10、Flutter bridge contract v35、业务缓存schema v6。凭据仅由既有verify入口从主区只读.env.local读取并通过stdin转交，实施区未复制凭据。所有验证不执行学校业务写入。

`just verify-live mode=webvpn`退出0，聚合矩阵完成。`just verify-live mode=direct`退出5：SPOC assignments/diagnostics在约12.7秒报告network_error，detail因此BLOCKED；其他所列聚合步骤完成。Direct没有通过整体只读门禁。两条路线旧聚合评教均返回空集合，沿历史容错语义，**不能证明新分段评教激活成功**。新App首页/分段/设备验收另行记录。

首次Direct启动因实施区没有.env.local而在任何学校请求前退出2；显式引用主区只读路径后执行了上述一轮，不创建实施区凭据副本。

日志保存在仓库外私有目录 `/Users/moorefoss/.local/share/ubaa-private-evidence/offline-home-20260917/p4ag-write-readback-20260923/`。

| 日志 | SHA-256 |
|---|---|
| ubaa-p4ag-live-direct.log | `b3814d233cec7cd0f44898282b449d7e18b876afcc6ea37d2045f121271bfb9c` |
| ubaa-p4ag-live-webvpn.log | `863a6a6ce44abd2de61689c57077aef3f320391be9e5ad2dbc5f8c8bd860d831` |
| ubaa-p4ag-sensitive.log | `0cf0b32c95371254f2b12fb68ae304900993f8a8ae21b353364abae71765b2a5` |
