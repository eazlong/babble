# Quest Service 事件驱动同步 — 验证合约

## 验证合约

| 断言 ID | 描述 | 验证方法 | 优先级 |
|---------|------|---------|--------|
| VC-001 | POST /api/v1/quests/report 能正确记录任务完成状态 | 调用接口后查询 status 接口确认 completed_quest_ids 包含该 quest | P0 |
| VC-002 | 重复报告同一 quest 不重复计算 LXP 和星星 | 同一 quest_id 报告两次，LXP 不翻倍 | P0 |
| VC-003 | 完成场景所有 sub-quest 后自动解锁徽章 | 依次报告 3 个 sub-quest，最后返回 badge_unlocked | P0 |
| VC-004 | GET /api/v1/quests/status 正确返回已完成/未完成列表 | 完成部分 quest 后调用，completed_quest_ids 和 pending_quest_ids 正确 | P0 |
| VC-005 | SpiritForestController 进入场景时查询后端状态并跳过已完成内容 | 模拟后端返回 completed_quest_ids，客户端跳过对应步骤 | P0 |
| VC-006 | 每个任务节点完成后调用 report_quest_complete 上报 | 在代码中确认 greet_oakley/activate_flowers/open_chest 完成后均有 API 调用 | P0 |
| VC-007 | HybridAPI.report_quest_complete 正确组装请求体并发送 POST | 检查 HybridAPI.gd 中方法实现 | P0 |
| VC-008 | 后端返回 badge_unlocked 后客户端正确显示徽章动画 | 模拟返回 badge，客户端 BadgeUI 显示 | P0 |
| VC-009 | 后端不可达时客户端游戏流程不受影响（fire-and-forget） | 停止 quest-service，客户端流程仍能完成 | P1 |
| VC-010 | quest-service 新增测试覆盖率 | 运行 pnpm test --filter=quest-service，测试通过 | P1 |
