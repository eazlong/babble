# Spirit Coach System GDD

**系统名称**: Spirit Coach System (精灵教练系统)
**版本**: 1.1（跨文档对齐修订）
**日期**: 2026-06-25
**所属游戏**: LinguaQuest RPG (babble)
**负责服务**: spirit-coach-service, Godot CoachOverlay
**依赖系统**: voice-service, dialogue-service, assessment-service, Redis Streams

**修订记录（v1.1, 2026-06-25）**:
- 沉默阈值 15s → 10s（对齐 core-loop.md `silence_threshold_s = 10`）
- 新增 §3.6 飞飞 示范模式（对齐 game-concept.md/core-loop.md/lxp-system.md: ASR 连续失败 2 次）
- 澄清示范模式与 DDR 的两层关系（2 次 vs 3+ 次触发阈值）
- Player Fantasy 添加言灵灵光叙事框架（对齐 game-concept.md）
- MAX_SILENCE_PER_SESSION 5 → 3（对齐 core-loop.md `spark_intervention_max = 3`）

---

## 1. Overview

**飞飞 角色定义**：飞飞 是玩家在游戏世界中的**随身精灵伙伴**，既是故事中的 NPC 角色（陪伴、对话、任务引导），也是后台 AI Agent 的视觉化身（异步监控、干预提示）。飞飞 具有**双模式架构**：

- **NPC 模式**：玩家主动与 飞飞 对话，完成教学引导、任务介绍、情感互动
- **Agent 模式**：系统异步检测玩家状态（错误/沉默/求助），飞飞 主动浮现提供干预提示

**系统定位**：Spirit Coach 是旁路辅助系统，不阻塞主对话流程。当玩家出现学习困难时，飞飞 以非侵入方式浮现，提供鼓励式提示，然后自动淡出，将焦点还给 NPC 对话。

---

## 2. Player Fantasy

**玩家体验目标**："飞飞 是我的灵兽伙伴，我遇到困难时它总会出现帮我"

**叙事包装（与 game-concept.md "言灵灵光"框架对齐）：**
飞飞 是玩家迷雾岛冒险中的**同伴精灵**——它不评判玩家的言灵灵光强弱，而是在玩家需要时温柔出现，帮助激活更强的言灵。飞飞 的提示和鼓励是"灵兽伙伴的支持"，而非"系统的纠正"。

**情感设计（MDA 美学）**：
- **Fellowship（陪伴感）**：飞飞 像朋友一样存在，不是冷冰冰的提示框
- **Expression（表达支持）**：飞飞 的提示鼓励而非评判，让玩家敢开口
- **Submission（安心感）**：知道 飞飞 会在困难时出现，降低尝试焦虑

**角色一致性保证**：
- 无论 NPC 模式还是 Agent 模式，飞飞 的**视觉形象一致**（同一只精灵）
- **性格一致**：温柔、鼓励、耐心，从不批评
- **出现方式一致**：从屏幕边缘飞入，气泡对话，自动淡出

---

## 3. Detailed Rules

### 3.1 飞飞 双模式架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        飞飞 (统一实体)                          │
├─────────────────────┬───────────────────────────────────────────┤
│     NPC 模式         │               Agent 模式                   │
│   (主动对话)         │           (异步干预)                        │
├─────────────────────┼───────────────────────────────────────────┤
│ • 玩家点击 飞飞     │ • 系统监控触发 (Redis Streams)            │
│ • 飞飞 主动搭话     │ • 错误检测 → 冷却判断 → 干预生成           │
│ • 任务引导和教学     │ • WebSocket 推送到 Godot                   │
│ • 情感互动和问候     │ • CoachOverlay 显示提示                    │
│ • 使用 DialogueSystem│ • 不阻塞主 NPC 对话                        │
└─────────────────────┴───────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   CoachOverlay   │
                    │   (7 状态显示层)  │
                    └──────────────────┘
```

**模式切换规则**：
- NPC 模式优先级高于 Agent 模式（如果玩家正在与 飞飞 对话，不触发干预）
- Agent 模式触发时，如果 飞飞 已在屏幕中（NPC 模式），直接显示气泡提示
- 两种模式共享同一个 CoachOverlay 实例

### 3.2 CoachOverlay 7 状态系统

**状态定义与优先级**（数值越高，优先级越高）：

| 状态 | 常量 | 优先级 | 视觉表现 | 触发条件 |
|------|------|--------|----------|----------|
| `idle` | STATE_IDLE | 0 | 呼吸动画，轻微上下浮动 | 默认状态，无活动 |
| `thinking` | STATE_THINKING | 1 | 思考动画，亮度提升 | 收到干预请求，正在准备 |
| `happy` | STATE_HAPPY | 2 | 跳跃庆祝动画，缩放脉冲 | 玩家连续正确、任务完成 |
| `hint` | STATE_HINT | 3 | 提示状态，缓慢浮动 | 显示沉默/错误提示 |
| `speaking` | STATE_SPEAKING | 4 | 说话动画，较快浮动 | 正在播放 TTS |
| `enter` | STATE_ENTER | 5 | 飞入动画，透明度+缩放 | 飞飞 进入屏幕 |
| `exit` | STATE_EXIT | 6 | 淡出动画，缩小消失 | 飞飞 离开屏幕 |

**状态切换规则**：
```gdscript
# 优先级门控：新状态优先级 >= 当前状态优先级才允许切换
# 例外：同状态刷新（如连续提示）允许覆盖
if new_priority < current_priority and not same_state_refresh:
    return  # 拒绝切换
```

**气泡显示规则**：
- 仅在 `speaking` 和 `hint` 状态显示气泡
- 气泡 TTL（生存时间）到期后自动隐藏
- 隐藏气泡时如果状态是 `speaking` 或 `hint`，自动回到 `idle`

### 3.3 Agent 模式触发器（3 类）

**触发器分类与优先级**：

| 触发器 | 类型 | 优先级 | 冷却时间 | 触发条件 |
|--------|------|--------|----------|----------|
| `wake` | 主动求助 | 3（最高） | 无冷却 | 玩家说唤醒词（"help", "帮帮我", "我不会"） |
| `error` | 错误干预 | 2 | 20 秒 | ErrorDetector 检测到 high severity 错误 |
| `silence` | 沉默干预 | 1 | 30 秒 | 玩家沉默 >= 10 秒 |

**触发流程**：
```
玩家行为 ──▶ Redis Stream (coach.input) ──▶ TriggerClassifier 分类
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
               dialogue_turn             silence_timeout           wake_request
                    │                         │                         │
                    ▼                         ▼                         ▼
            ErrorDetector 分析          直接标记 silence          直接标记 wake
            提取 high severity              │                         │
                    │                       │                         │
                    └───────────┬───────────┴─────────────────────────┘
                                ▼
                        InterventionPolicy 决策
                    （检查冷却、优先级、并发）
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
              should_intervene=false    should_intervene=true
                    │                       │
                    ▼                       ▼
              丢弃事件               CoachHintGenerator 生成提示
                                          │
                                          ▼
                                    WebSocket 推送
                                          │
                                          ▼
                              Godot CoachOverlay 显示
```

**干预内容格式**：
```typescript
interface CoachIntervention {
  event_id: string           // 唯一事件 ID
  session_id: string          // 会话 ID
  user_id: string             // 用户 ID
  trigger: 'wake' | 'error' | 'silence'
  priority: number            // 1-3
  text: string                // 气泡显示文本（中英双语）
  repeat_phrase: string      // 可跟读短句（可选）
  emotion: string             // CoachOverlay 情绪状态
  should_tts: boolean        // 是否播放 TTS
  ttl_ms: number              // 气泡显示时长（毫秒）
  timestamp: number           // 时间戳
}
```

### 3.4 冷却策略（防止过度干预）

**冷却键结构**：
```
cooldown:{user_id}:spirit:error    → TTL 20 秒
cooldown:{user_id}:spirit:silence  → TTL 30 秒
# wake 无冷却键，始终响应
```

**冷却逻辑**：
```typescript
async shouldIntervene({ trigger, userId }) {
  if (trigger === 'wake') return true  // 主动求助无冷却

  const cooldownKey = `cooldown:${userId}:spirit:${trigger}`
  const value = await redis.get(cooldownKey)
  return value === null  // key 不存在 = 冷却已过
}

async markIntervened({ trigger, userId }) {
  if (trigger === 'wake') return  // 不标记冷却

  const ttl = trigger === 'error' ? 20 : 30
  await redis.set(`cooldown:${userId}:spirit:${trigger}`, '1', 'EX', ttl)
}
```

### 3.5 错误检测规则（ErrorDetector）

**统一困难指标**（与 quest-system.md 对齐）：

建立跨系统共享的 `player_struggle_score`，避免两套降级标准：

```typescript
struggle_score = (
  (consecutive_low_lxp >= 3 ? 1 : 0) +  // LXP < 40（来自 assessment）
  (consecutive_errors >= 3 ? 1 : 0) +    // grammar/pronunciation 错误
  (asr_failure_rate > 0.5 ? 1 : 0)       // ASR 置信度 < 0.3 的比例
) / 3

if struggle_score >= 0.67:
  trigger_spark_intervention()           // 飞飞 介入
  activate_quest_ddr()                   // Quest 系统降级
```

**错误类型与严重度**：

| 错误类型 | 严重度 | 检测规则（MVP） | 示例 |
|----------|--------|-----------------|------|
| grammar | high | 匹配常见错误模式 | "I am go" → "I go / I am going" |
| grammar | high | 主谓不一致 | "he don't" → "he doesn't" |
| vocabulary | medium | 使用非课标词汇（不触发干预）| - |
| pronunciation | high | ASR confidence < 0.3（上游处理）| - |

**严重度过滤**：只有 `high` 严重度错误触发 `error` 触发器。

**降级触发逻辑**：
- 当 `struggle_score >= 0.67` 时，同时触发：
  - 飞飞 Agent 模式介入（显示鼓励提示）
  - Quest 系统难度降级（降低任务类型）
  - Star Economy 保底机制（最低 2 星）
- 确保玩家体验到统一的支持，而非分裂的标准

### 3.6 飞飞 示范模式（ASR Fallback）

> **对齐说明**: 此机制与 game-concept.md §9、core-loop.md §3.1、lxp-system.md §5 的示范模式定义一致。

**触发条件**：同一任务 ASR 连续失败 2 次（ASR confidence < 0.3 或 text 为空）。

**示范模式流程**：
1. 飞飞 暂停当前任务评估
2. NPC 通过 TTS 播放正确发音（示范朗读目标词句）
3. 玩家跟读，跟读结果进入 LXP 评估流程
4. **跟读成功**（LXP >= 40）→ 计为任务完成，正常获得星级
5. **跟读仍失败** → lxp-system 保底机制生效，最低 40 分（2 星），任务仍计为完成
6. 全程不引入文字输入（保持"纯语音交互"支柱）

**示范模式与 DDR 的关系**（两层降级，触发阈值不同）：

| 层级 | 触发条件 | 响应系统 | 效果 |
|------|---------|---------|------|
| **第一层：示范模式** | ASR 连续失败 **2 次** | Spirit Coach + LXP | NPC 播放正确发音，玩家跟读 |
| **第二层：DDR（动态难度调整）** | `struggle_score >= 0.67`（连续错误 **>= 3 次** + 连续低 LXP + ASR 高失败率） | Spirit Coach + Quest + Star Economy | 飞飞 鼓励提示 + 任务降级 + 保底 2 星 |

**关键区别**：
- 示范模式针对**单次任务的 ASR 失败**（局部问题，播放正确发音即可解决）
- DDR 针对**玩家整体困难状态**（跨任务、多维度信号，需要系统级降级）
- 示范模式在 2 次失败时触发，DDR 在 3 次及以上持续错误时触发
- 两者可同时生效：示范模式解决当前任务，DDR 调整后续任务难度

**连续失败计数器**（与 lxp-system.md §4.5 对齐）：
```
errorStreak:
  +1 when ASR failure detected (confidence < 0.3 or text empty)
  reset to 0 when correct answer or task changes

当 errorStreak == 2 → 触发示范模式
当 errorStreak >= 3 → 纳入 struggle_score 计算，可能触发 DDR
```

---

## 4. Formulas

### 4.1 冷却时间计算

$$T_{cooldown}(trigger) = \begin{cases}
0 & \text{if } trigger = wake \\
20 & \text{if } trigger = error \\
30 & \text{if } trigger = silence
\end{cases}$$

### 4.2 干预优先级排序

给定多个待处理干预，按 `priority` 字段降序排列：

$$P_{effective} = P_{trigger} + P_{time}$$

其中：
- $P_{trigger}$: 触发器基础优先级（wake=3, error=2, silence=1）
- $P_{time}$: 时间衰减（越小越优先，相同 $P_{trigger}$ 时先到先服务）

### 4.3 气泡显示时长

$$T_{display} = \max(T_{min}, T_{reading} + T_{tts})$$

| 变量 | 值 | 说明 |
|------|-----|------|
| $T_{min}$ | 3000ms | 最短显示时间 |
| $T_{reading}$ | $\text{len}(text) \times 150$ms | 阅读时间（每秒约 6-7 汉字）|
| $T_{tts}$ | 音频时长 | 如果 `should_tts=true` |

**MVP 默认值**：`ttl_ms = 8000`（固定 8 秒）

### 4.4 沉默检测阈值

$$T_{silence} \geq 10000 \text{ ms} \Rightarrow \text{触发 silence_timeout 事件}$$

上游系统（voice-service 或 Godot）负责检测沉默并写入 Redis Stream。

### 4.5 统一困难指标计算（跨系统对齐）

$$\text{struggle\_score} = \frac{S_{lxp} + S_{error} + S_{asr}}{3}$$

其中：
$$S_{lxp} = \begin{cases}
1 & \text{if } \text{consecutive\_low\_lxp} \geq 3 \\
0 & \text{otherwise}
\end{cases}$$

$$S_{error} = \begin{cases}
1 & \text{if } \text{consecutive\_errors} \geq 3 \\
0 & \text{otherwise}
\end{cases}$$

$$S_{asr} = \begin{cases}
1 & \text{if } \text{asr\_failure\_rate} > 0.5 \\
0 & \text{otherwise}
\end{cases}$$

**触发阈值**：
- $\text{struggle\_score} \geq 0.67$ → 飞飞 介入 + Quest DDR + Star 保底
- 三个系统同步响应，避免分裂体验

**连错追踪**：
$$
\text{errorStreak}_{new} = \begin{cases}
\text{errorStreak} + 1 & \text{if error detected} \\
0 & \text{if correct answer}
\end{cases}$$

$$\text{lowLxpStreak}_{new} = \begin{cases}
\text{lowLxpStreak} + 1 & \text{if LXP} < 40 \\
0 & \text{if LXP} \geq 40
\end{cases}$$

---

## 5. Edge Cases

### 5.1 多干预并发

**场景**：同一时刻产生多个触发器（如沉默时恰好检测到错误）

**处理规则**：
1. 按优先级排序：wake > error > silence
2. 只执行最高优先级的干预
3. 低优先级干预丢弃（不累积）

### 5.2 玩家快速连续求助

**场景**：玩家连续说 "help"

**处理规则**：
- wake 无冷却，每次都响应
- 但 `InterventionPolicy` 应限制同一秒内最多 1 次干预
- 后端通过 `event_id` 去重

### 5.3 网络中断恢复

**场景**：WebSocket 断开期间发生干预

**处理规则**：
- CoachClient 缓存最后状态到 `user://coach_session_state.cfg`
- 重连后恢复状态，不补发已错过的干预（避免过时提示）
- 重连成功显示 "飞飞 回来了" 的轻量提示

### 5.4 飞飞 已在屏幕中

**场景**：玩家正在与 飞飞（NPC 模式）对话时触发 Agent 干预

**处理规则**：
- NPC 模式优先级高于 Agent 模式
- 延迟干预，直到 NPC 对话结束
- 或：在 飞飞 气泡上方叠加一个小提示图标（非侵入式）

### 5.5 长文本截断

**场景**：生成的提示文本过长（> 100 字符）

**处理规则**：
- CoachOverlay 气泡最大高度限制
- 文本自动换行，超出滚动或截断
- MVP：限制生成文本长度在 80 字符内

### 5.6 TTS 失败

**场景**：`should_tts=true` 但 TTS 服务不可用

**处理规则**：
- 静默降级：只显示文本气泡
- 记录错误日志
- 不阻塞干预流程

### 5.7 重复干预疲劳

**场景**：同一类型干预频繁触发（如玩家持续沉默）

**处理规则**：
- 冷却策略已防止短时间内重复
- 同一 session 最多 3 次 silence 干预，之后忽略（与 core-loop.md `spark_intervention_max = 3` 对齐）
- error 干预每回合最多 1 次

### 5.8 Redis 不可用

**场景**：Redis 连接失败，无法检查冷却

**处理规则**：
- 默认不介入（`shouldIntervene` 返回 false）
- 避免无冷却保护下的干预轰炸
- 记录错误，通知运维

---

## 6. Dependencies

### 6.1 上游依赖（输入来源）

| 系统 | 数据 | 用途 |
|------|------|------|
| voice-service | ASRResult, silence events | 唤醒词检测、沉默触发 |
| dialogue-service | dialogue_turn events, player_text | 对话回合内容、错误检测输入 |
| assessment-service | errorStreak, score | 连错降级判断 |
| Redis Streams | coach.input stream | 统一事件总线 |

### 6.2 下游依赖（输出去向）

| 系统 | 数据 | 用途 |
|------|------|------|
| Godot CoachOverlay | CoachIntervention payload | 视觉呈现和 TTS |
| Redis Streams | coach.intervention stream | 事件持久化 |
| dialogue-service | difficulty_adjust suggestion | 连错降级反馈 |

### 6.3 内部组件依赖图

```
┌────────────────────────────────────────────────────────────┐
│                  spirit-coach-service                      │
├─────────────┬──────────────┬──────────────┬──────────────┤
│  coach-input │   trigger-   │ intervention │  coach-hint-   │
│  consumer   │  classifier  │   policy     │  generator   │
│             │              │              │              │
│  Redis订阅   │ 分类trigger   │ 冷却检查      │ 生成提示文本  │
│ 事件分发     │ 错误严重度    │ 优先级排序    │ 双语模板      │
└──────┬──────┴──────┬───────┴──────┬───────┴──────┬───────┘
       │             │              │              │
       ▼             ▼              ▼              ▼
┌────────────────────────────────────────────────────────────┐
│                error-detector.ts                          │
│   • 规则错误检测                                           │
│   • 课标词汇匹配                                           │
│   • 连错/连对追踪                                           │
└────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────┐
│              coach-session-manager.ts                      │
│   • WebSocket 连接管理                                      │
│   • 在线客户端推送                                          │
│   • 离线状态缓存                                            │
└────────────────────────────────────────────────────────────┘
```

---

## 7. Tuning Knobs

### 7.1 冷却时间参数

| 参数 | 位置 | 默认值 | 安全范围 | 类别 | 说明 |
|------|------|--------|----------|------|------|
| `COOLDOWN_ERROR` | `intervention-policy.ts` | 20s | 10-60s | Gate | 错误干预冷却 |
| `COOLDOWN_SILENCE` | `intervention-policy.ts` | 30s | 15-120s | Gate | 沉默干预冷却 |
| `SILENCE_THRESHOLD` | voice-service / Godot | 10000ms | 8000-15000 | Gate | 沉默检测阈值（与 core-loop.md `silence_threshold_s = 10` 对齐） |

### 7.2 触发器参数

| 参数 | 位置 | 默认值 | 安全范围 | 类别 | 说明 |
|------|------|--------|----------|------|------|
| `ERROR_STREAK_THRESHOLD` | `error-detector.ts` | 3 | 2-5 | Gate | 连错降级阈值 |
| `MAX_SILENCE_PER_SESSION` | `intervention-policy.ts` | 3 | 2-5 | Gate | 单会话最大沉默干预数（与 core-loop.md `spark_intervention_max = 3` 对齐） |
| `MAX_ERROR_PER_TURN` | `intervention-policy.ts` | 1 | 1-3 | Gate | 单回合最大错误干预数 |

### 7.3 显示参数

| 参数 | 位置 | 默认值 | 安全范围 | 类别 | 说明 |
|------|------|--------|----------|------|------|
| `BUBBLE_TTL_DEFAULT` | `CoachHintGenerator` | 8000ms | 5000-15000 | Feel | 气泡默认显示时长 |
| `BUBBLE_TTL_MIN` | `CoachOverlay.gd` | 3000ms | 2000-5000 | Feel | 气泡最短显示时长 |
| `TTS_ENABLED` | `CoachIntervention` | true | true/false | Feel | 是否默认启用 TTS |

### 7.4 优先级参数

| 参数 | 位置 | 默认值 | 安全范围 | 类别 | 说明 |
|------|------|--------|----------|------|------|
| `PRIORITY_WAKE` | `coach-events.ts` | 3 | 3-5 | Gate | 唤醒优先级 |
| `PRIORITY_ERROR` | `coach-events.ts` | 2 | 2-4 | Gate | 错误优先级 |
| `PRIORITY_SILENCE` | `coach-events.ts` | 1 | 1-3 | Gate | 沉默优先级 |

### 7.5 WebSocket 参数

| 参数 | 位置 | 默认值 | 安全范围 | 类别 | 说明 |
|------|------|--------|----------|------|------|
| `MAX_RECONNECT_ATTEMPTS` | `CoachClient.gd` | 3 | 2-5 | Gate | 最大重连次数 |
| `MAX_RECONNECT_DELAY` | `CoachClient.gd` | 10s | 5-30s | Gate | 最大重连间隔 |
| `CONNECT_TIMEOUT` | `CoachClient.gd` | 10s | 5-15s | Gate | 连接超时 |

---

## 8. Acceptance Criteria

### 8.1 功能测试

- [ ] 玩家说 "help" → 3 秒内 飞飞 显示 "我来帮你！你可以说：Can you help me?"
- [ ] 玩家沉默 10 秒 → 飞飞 显示鼓励提示，30 秒内不重复触发（与 core-loop.md 对齐）
- [ ] 玩家说 "I am go" → 飞飞 显示 "差一点点！可以说：I am going"
- [ ] 同一错误在 20 秒内重复 → 只触发一次干预
- [ ] NPC 模式下不触发 Agent 干预
- [ ] ASR 连续失败 2 次 → 飞飞 示范模式触发：NPC 播放正确发音，玩家跟读
- [ ] 示范模式跟读成功（LXP >= 40）→ 计为任务完成，正常获得星级
- [ ] 示范模式跟读仍失败 → 保底 40 分（2 星），任务仍计为完成

### 8.2 边界测试

- [ ] WebSocket 断开 30 秒后重连 → 不崩溃，不显示过时提示
- [ ] 玩家连续说 10 次 "help" → 每次响应，但同一秒内只处理一次
- [ ] Redis 不可用 → 静默降级，不崩溃
- [ ] 气泡文本 > 100 字符 → 正确换行显示

### 8.3 性能测试

- [ ] 单次干预从触发到显示 < 500ms（P95）
- [ ] 并发 100 会话，干预生成正常
- [ ] WebSocket 重连时间 < 3 秒

### 8.4 集成测试

- [ ] voice-service → spirit-coach-service → Godot 链路完整
- [ ] TTS 播放与气泡显示同步
- [ ] 冷却键正确过期，过期后可再次触发

### 8.5 体验测试

- [ ] 6-10 岁测试玩家能正确理解 飞飞 的提示意图
- [ ] 测试玩家不感到 飞飞 干扰正常游戏
- [ ] 飞飞 的鼓励语气符合儿童心理预期

---

## 9. 角色一致性声明

**本 GDD 正式确认**：

> 飞飞 是 LinguaQuest RPG 中的**统一精灵角色**，既作为玩家主动对话的 NPC 伙伴，也是系统异步监控的 AI Agent 视觉化身。
>
> 两种模式（NPC 模式与 Agent 模式）使用**相同的视觉形象、性格设定和交互风格**，确保儿童玩家的认知一致性。
>
> "Spirit Coach" 是系统层面的功能名称，指代后端 AI 监控与干预能力，其视觉呈现始终是 飞飞 角色。

**文档历史澄清**：
- SRS 中的 "Spirit Coach Agent" → 指代后端系统的异步监控能力
- 剧情设计中的 "飞飞" → 指代统一的精灵角色
- 无角色分裂，无第二精灵实体

---

## 下一步

1. `/design-review design/gdd/spirit-coach.md` — 审查此 GDD
2. `/design-system dialogue-system` — 确保与主对话系统协调
3. `/consistency-check` — 检查变量名和事件名一致性
4. 补充 CoachOverlay 单元测试（7 状态覆盖）
