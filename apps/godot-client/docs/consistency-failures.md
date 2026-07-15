# Consistency Failure Log

<!-- Auto-maintained by /consistency-check. Do not edit manually. -->
<!-- One entry per detected conflict, in chronological order. -->

| Date | GDD A | GDD B | Conflict Type | Status |
|------|-------|-------|---------------|--------|
| 2026-06-25 | star-economy.md | quest-system.md | 🔴 Badge 阈值动态 vs 硬编码 20 | ✅ Fixed |
| 2026-06-25 | star-economy.md | lxp-system.md | 🔴 保底星星 1 vs 2 语义不清 | ✅ Fixed |
| 2026-06-25 | game-concept.md | core-loop.md | 🟡 场景时长 10-20min vs 8-12min | ✅ Fixed |
| 2026-06-25 | spirit-coach.md | core-loop.md | 🔴 沉默阈值 15s vs 10s | ✅ Fixed |
| 2026-06-25 | spirit-coach.md | game-concept.md | 🔴 示范模式缺失 | ✅ Fixed |
| 2026-06-25 | spirit-coach.md | core-loop.md | 🟡 session 干预上限 5 vs 3 | ✅ Fixed |

---

### 2026-06-25 — /consistency-check — 🔴 CONFLICT (Batch)
**Domain**: Economy, Spirit Coach, Core Loop
**Documents involved**: quest-system.md vs star-economy.md / spirit-coach.md vs core-loop.md / game-concept.md vs core-loop.md
**What happened**:
1. quest-system 硬编码 `targetStars = 20`，但 star-economy 定义动态阈值公式（SpiritForest 中等玩家 = 15 星）
2. star-economy `MIN_STARS_GUARANTEE = 1` 与 lxp-system `MIN_SCORE_RETRY_3 = 40`（2 星）语义重叠
3. game-concept 场景时长 10-20 分钟与 core-loop 8-12 分钟冲突；AC 中"单场景 20-30 分钟"应为"单会话"
4. spirit-coach 沉默阈值 15s 与 core-loop 10s 冲突
5. spirit-coach 缺少 Feifei 示范模式定义（game-concept/core-loop/lxp-system 均有）
6. spirit-coach `MAX_SILENCE_PER_SESSION = 5` 与 core-loop `feifei_intervention_max = 3` 冲突

**Resolution**: 全部修复 — quest-system 改为引用动态阈值函数；star-economy 添加基础保底/困难保底分层说明；game-concept 场景时长对齐 8-12 分钟、AC 改为"单会话 20-30 分钟"；spirit-coach 沉默阈值改为 10s、新增 §3.6 示范模式、session 上限改为 3

**Pattern**: 多个 GDD 并行编写时，共享参数（阈值、时长、触发条件）未同步更新。建议在每次修订一个 GDD 后立即运行 /consistency-check，而非等所有 GDD 完成后才检查。
