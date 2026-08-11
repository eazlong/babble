# 诊断层经 auth-service 代理消费，独立端点，家长可见诊断裁剪

家长端不直连 summary-service，由 auth-service 新增 `/parent/:parentId/diagnosis` 端点代理转发。代理职责：校验家长对该 child 的监护关系（复用现有 child_accounts 校验）、调用 summary-service `/summary/report/diagnosis`、按"家长可见诊断"裁剪规则剥掉内部状态（保留强度数值、半衰期、上次掌握分、补评依据、升级信号、ASR 文本）后返回。诊断独立成端点，不与现有 `/reports`（运营指标）合并——领域边界、数据源、故障域、缓存策略均不同。

**Considered Options**:
- auth-service 代理 + 独立端点（采用）——领域裁剪归后端，认证统一，单后端入口。
- 家长端直连 summary-service（拒）——summary-service 诊断端点无认证，child_id 可枚举，孩子诊断是敏感数据；且领域裁剪会泄露到前端。
- 扩展现有 `/reports` 合并诊断（拒）——焊接不同领域概念与故障域，summary-service 挂则整个 reports 页挂。

**Consequences**:
- auth-service 新增对 summary-service 的同步 HTTP 依赖；summary-service 不可用时家长端诊断降级为"诊断生成中"，不影响运营指标。
- auth-service 名实不符（实际承载认证 + 家长业务 dashboard/reports/time-limit/delete-data + 诊断代理）的已知债持续累积。正名（auth-service → parent-service）应作为独立 refactor 任务，不在此 MVP 混做。
