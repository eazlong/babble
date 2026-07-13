# Tickets: LLM Coach 实现

为 spirit-coach-service 引入 LLM 教练，替换现有纯规则引擎。参考规格说明：[llm-coach-spec.md](services/spirit-coach-service/docs/llm-coach-spec.md)。

按 **frontier** 推进：从没有 blocker 的 ticket 开始，完成后解锁下游。

---

## Ticket 1: 服务端 LLM 教练核心

**Blocked by**: None — 可以立即开始

**What to build**: 完整的后端 LLM 教练管线。扩展 `coach.input` schema（`player_level` 可选，默认 `'A1'`；`recent_turns` 可选，默认 `[]`），实现 `LLMCoach` 模块（可配置模型，默认 GPT-4o-mini，环境变量 `COACH_LLM_MODEL`）、`PromptBuilder`、`ContextAssembler`、`Fallback templates`，集成到 `CoachInputConsumer`（5s 超时 + fallback）。Schema 测试验证输出格式。

**关键决策**（来自 spec）:
- 混合分层：规则层（`TriggerClassifier`、`InterventionPolicy`）保留；`ErrorDetector.analyze()` 仅保留触发器分类职责，纠正文本生成被 LLM 替换；`CoachHintGenerator.generate()` 整体退役
- 单次 LLM 调用同时做错误检测 + 响应生成
- Prompt 架构：`prompts/system.txt`（人设 + 规则）作为 system 角色，`prompts/context-{trigger}.txt`（动态注入）作为 user 角色
- 输出 schema：LLM 返回 `{text, emotion, repeat_phrase, should_tts, ttl_ms}`，服务端填充 `{event_id, session_id, user_id, trigger, priority, timestamp}`
- 向后兼容：新字段可选 + 默认值，旧客户端无需立即更新

**Acceptance criteria**:
- [ ] `coach.input` schema 新增可选字段 `player_level`（默认 `'A1'`）和 `recent_turns`（默认 `[]`），旧客户端仍可正常调用
- [ ] `LLMCoach` 模块调用 OpenAI API，模型从 `COACH_LLM_MODEL` 环境变量读取（默认 `gpt-4o-mini`）
- [ ] `PromptBuilder` 从 `prompts/` 目录读取模板，区分 system 角色和 user 角色
- [ ] `CoachInputConsumer` 集成 LLM 调用，5s 超时，失败时走 fallback 模板
- [ ] Fallback 模板覆盖三种 trigger（wake / silence / error）
- [ ] 输出到 `coach.intervention` Redis stream 和 WebSocket，格式与现有 `CoachIntervention` schema 一致
- [ ] Schema 测试验证 LLM 输出格式（text 30-300 字符、emotion 枚举、should_tts 布尔值）
- [ ] Demo：通过 `POST /api/v1/coach/events` 发送 `dialogue_turn` 事件 → 收到 LLM 生成的纠正响应

---

## Ticket 2: 客户端上报对话上下文

**Blocked by**: Ticket 1

**What to build**: 客户端维护对话历史滑动窗口（最近 5 轮 player/npc 对话），集成到 3 个场景（SpiritForest、SpellLibrary、RainbowGarden）的 NPC 对话系统。发送 coach 事件时附带 `player_level` 和 `recent_turns`。

**关键数据结构**:
```gdscript
# CoachContextTracker（新增）
const MAX_TURNS = 5
var _turns: Array[Dictionary] = []  # 最多 MAX_TURNS*2 条消息
func add_turn(speaker: String, text: String) -> void
func get_recent_turns() -> Array[Dictionary]
```

**Acceptance criteria**:
- [ ] 新增 `CoachContextTracker` 类，维护最近 5 轮（10 条消息）滑动窗口
- [ ] 3 个场景的 NPC 对话系统集成 `CoachContextTracker`：玩家说话时 `add_turn("player", text)`，NPC 回应时 `add_turn("npc", text)`
- [ ] 发送 coach 事件时附带 `player_level`（从 session 状态读取）和 `recent_turns`（从 tracker 读取）
- [ ] 场景切换或 session 结束时 `clear()` tracker
- [ ] Demo：玩家在 NPC 对话中说话 → 服务端收到 `recent_turns` 包含最近对话历史 → LLM 响应体现对话上下文

---

## Ticket 3: Streak tracking 接入

**Blocked by**: Ticket 1

**What to build**: 从 `ErrorDetector` 抽离 `StreakTracker` 模块（`recordError`/`recordCorrect`/`getErrorStreak`/`getCorrectStreak`/`shouldReduceDifficulty`/`checkStreakReward`），集成到 `CoachInputConsumer` 主流程。Prompt 动态注入 streak 数据（`{{error_streak}}`、`{{correct_streak}}` 占位符）。

**背景**: 现有 `ErrorDetector` 中的 streak tracking 代码已实现并测试，但从未在主流程调用（孤儿代码）。本次抽离为独立模块并接入。

**Acceptance criteria**:
- [ ] 新增 `StreakTracker` 模块（从 `ErrorDetector` 抽出 streak 相关方法），独立可测试
- [ ] `CoachInputConsumer` 在处理每个事件时调用 `streakTracker.recordError/recordCorrect`
- [ ] `buildPrompts()` 注入 `error_streak` 和 `correct_streak` 变量到 context 模板
- [ ] `context-error.txt` 模板包含 streak 占位符（条件渲染）
- [ ] Demo：模拟连续 3 次错误 → LLM 响应体现"降低难度、多鼓励"；模拟连续 3 次正确 → LLM 响应体现"表扬"

---

## Ticket 4: 集成测试

**Blocked by**: Tickets 1, 2, 3

**What to build**: 10 个典型场景的集成测试，覆盖 LLM 教练在各种输入下的行为。

**测试用例**（来自 spec 7.2）:
1. A1 玩家说 "I am go" → 纠正为 "I go" 或 "I am going"
2. A1 玩家沉默 15s → 中文鼓励 + 简单英文提示
3. B2 玩家说 "He don't like it" → 纠正为 "He doesn't"，英文为主
4. 玩家 wake request "help me" → 提供帮助
5. A1 玩家连续 3 次错误 → 降低难度、多鼓励
6. B1 玩家连续 3 次正确 → 表扬、可能提升挑战
7. 玩家说中文（非目标语言）→ 温和提醒用英文
8. 玩家说很长很正确的句子 → 表扬
9. 玩家说完全无关的话 → 温和引导回主题
10. LLM 超时 → 使用 fallback 模板

**Acceptance criteria**:
- [ ] 10 个测试用例全部通过
- [ ] 测试覆盖三种 trigger（dialogue_turn / silence_timeout / wake_request）
- [ ] 测试覆盖不同 player_level（A1 / B2）的语言比例
- [ ] 测试覆盖 streak 自适应行为
- [ ] 测试覆盖 LLM 超时 fallback

---

## Ticket 5: 监控告警

**Blocked by**: Ticket 1

**What to build**: 监控 fallback 频率、LLM 延迟分布、成本（调用次数 + token 消耗）。告警阈值（fallback > 5%）。

**Acceptance criteria**:
- [ ] 每次 LLM 调用记录延迟（ms）、是否 fallback、token 消耗
- [ ] Metrics 暴露（Prometheus 或类似）
- [ ] Fallback 频率 > 5% 时告警
- [ ] Dashboard 可查看日均调用次数、成本、延迟 P50/P95

---

## Ticket 6: LLM-as-judge 质量评估

**Blocked by**: Ticket 4

**What to build**: 用另一个 LLM 自动评估教练输出质量（是否符合小飞猫人设、是否友善、是否正确纠正、语言比例是否匹配 player_level）。集成到 CI。

**Acceptance criteria**:
- [ ] 评估 prompt 定义质量维度（人设一致性、友善度、纠正准确性、语言比例）
- [ ] CI 中运行质量检查，对集成测试的输出自动评分
- [ ] 低于阈值时报错阻断 CI

---

## 依赖关系图

```
Ticket 1 (服务端核心) ──┬──→ Ticket 2 (客户端上报)
                        ├──→ Ticket 3 (Streak tracking)
                        └──→ Ticket 5 (监控告警)

Ticket 2, 3 ──→ Ticket 4 (集成测试) ──→ Ticket 6 (LLM-as-judge)
```

**Frontier**（当前可开始）: Tickets 1, 3, 5（但建议先完成 Ticket 1，再并行推进 2、3、5）
