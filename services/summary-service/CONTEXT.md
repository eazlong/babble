# summary-service Context

学习总结与掌握度服务。消费已评分交互尝试（含深度补评），用半衰期模型聚合掌握度，产出玩家视图与策划诊断视图报告。诊断层只描述"学得怎么样"，处方层（下次内容）由 quest-service 生成。见根 `CONTEXT.md` "学习总结与掌握度" 与 ADR 0002-0005。

## 边界

- **消费**：assessment-service 评分、voice-service ASR 重跑（后续阶段）、客户端上报的交互尝试。
- **产出**：掌握度状态（`child_data.mastery_state`）、玩家报告、策划诊断报告。
- **不产出**：下次内容处方（quest-service 职责）、实时快评（assessment-service / 客户端职责）。

## 数据表

- `child_data.learning_sessions` — 游戏会话
- `child_data.prompt_turns` — 提示轮次（含内容快照）
- `child_data.interaction_attempts` — 交互尝试（绑定录音/ASR/评分/知识项）
- `child_data.mastery_state` — 掌握度状态（半衰期、保留强度、档位）

## 端点

- `POST /api/v1/summary/{sessions,prompt-turns,interaction-attempts}` — 上报
- `GET /api/v1/summary/mastery` — 查掌握度
- `POST /api/v1/summary/mastery/recompute` — 重算
- `GET /api/v1/summary/report/{player,diagnosis}` — 两视图报告
- `POST /api/v1/summary/deep-assess/{batch,escalate-llm}` — 补评（batch 第一版占位，escalate-llm 预留 501）
