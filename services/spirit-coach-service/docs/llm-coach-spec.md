# LLM Coach 实现规格说明

> **目的地**：为 spirit-coach-service 引入 LLM 教练，替换现有的纯规则引擎，实现个性化的错误纠正、沉默鼓励、主动帮助。
>
> **状态**：规格已定稿，等待实现。

---

## 1. 概览

### 1.1 当前状态

spirit-coach-service 是纯规则引擎：
- `ErrorDetector.analyze()` — 只有 2 个正则（`i am go` → `I go`/`he don't` → `he doesn't`）
- `CoachHintGenerator.generate()` — 硬编码模板字符串（小飞猫人设）
- 注释写着 "MVP: Rule-based error detection, LLM analysis in production"

### 1.2 目标

用 LLM 替换 ErrorDetector + CoachHintGenerator，实现：
- **智能错误检测**：覆盖所有语法/词汇/语用错误（不再限于 2 个正则）
- **个性化响应**：根据 player_level、对话历史、错误连续次数动态调整
- **自然语言生成**：响应不再是固定模板，而是 LLM 生成的个性化文本

### 1.3 核心决策

| # | 决策点 | 选择 |
|---|--------|------|
| 1 | LLM vs 规则引擎 | **混合分层**（规则做粗筛，LLM 做精细判断和响应生成） |
| 2 | LLM 调用位置 | **替换 ErrorDetector + CoachHintGenerator**（单次调用） |
| 3 | Prompt 架构 | **单一 prompt + 动态注入**（trigger、player_level、recent_turns、streak） |
| 4 | LLM 模型 | **可配置，默认 GPT-4o-mini**（环境变量 `COACH_LLM_MODEL`） |
| 5 | 输出 schema | **语义内容**（text, emotion, repeat_phrase 等）+ **服务端元数据**（event_id, timestamp 等） |
| 6 | 上下文注入 | **输入 + profile + 对话历史** |
| 7 | 对话历史 | **滑动窗口 5 轮 + 客户端上报** |
| 8 | PlayerLevel | **客户端每次事件上报** |
| 9 | Streak tracking | **抽离独立模块 + 注入 LLM**（Phase 2） |
| 10 | 超时/回退 | **5 秒超时 + 规则模板回退** |
| 11 | 客户端改动 | **规格包含客户端设计** |
| 12 | 测试策略 | **Schema 测试（MVP）+ 集成测试（Phase 2）** |
| 13 | MVP 范围 | **核心 LLM 调用 + 客户端上报 player_level + recent_turns** |
| 14 | 向后兼容 | **新字段可选 + 默认值**（player_level='A1', recent_turns=[]） |
| 15 | Prompt 存放 | **外部文件**（prompts/system.txt + context-*.txt） |

---

## 2. 架构

### 2.1 混合分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Coach Input Consumer                      │
│                                                              │
│  Redis Stream → Parse → TriggerClassifier → Policy Check    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              LLM Coach (新增)                         │   │
│  │                                                        │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐  │   │
│  │  │ Prompt      │  │ LLM Client   │  │ Response    │  │   │
│  │  │ Builder     │→ │ (4o-mini)    │→ │ Parser      │  │   │
│  │  └─────────────┘  └──────────────┘  └─────────────┘  │   │
│  │         ↑                                    ↓         │   │
│  │  ┌─────────────┐                    ┌─────────────┐   │   │
│  │  │ Context     │                    │ Fallback    │   │   │
│  │  │ Assembler   │                    │ (规则模板)   │   │   │
│  │  └─────────────┘                    └─────────────┘   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  → Output (Redis Stream + WebSocket)                        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 规则层保留

以下模块保留，不做改动：
- `TriggerClassifier` — 分类 trigger（wake/silence/error）
- `InterventionPolicy` — 冷却策略（error=20s, silence=30s）
- `CoachSessionManager` — WebSocket session 管理

### 2.3 规则层部分退役

`ErrorDetector.analyze()` 有两个职责，只有第二个被替换：

| 职责 | 处理方式 |
|------|---------|
| 触发器分类（判断 dialogue_turn 是否有 high-severity 错误） | **保留** — `TriggerClassifier` 仍然调用它 |
| 生成纠正文本（correction, explanation） | **被 LLM 替换** — LLM 同时做错误分析和响应生成 |

完全退役的模块：
- `CoachHintGenerator.generate()` — 被 LLM 替换（响应生成）

保留但不再用于错误纠正文本生成的方法：
- `ErrorDetector.generateChineseExplanation()` — 不再需要（LLM 直接生成中文纠正）
- `ErrorDetector.checkCurriculumVocabulary()` — 可选保留（Phase 2 可作为 LLM 上下文注入）

### 2.4 新增模块

| 模块 | 文件 | 职责 |
|------|------|------|
| `LLMCoach` | `services/llm-coach.ts` | 调用 LLM，解析响应 |
| `PromptBuilder` | `services/prompt-builder.ts` | 组装 prompt（基础 + 动态注入） |
| `ContextAssembler` | `services/context-assembler.ts` | 从输入提取上下文（player_level, recent_turns） |
| `StreakTracker` | `services/streak-tracker.ts` | 错误/正确连续追踪（Phase 2） |

---

## 3. 数据流

### 3.1 输入事件（扩展）

```typescript
// coach.input Redis stream 消息格式（扩展后）
interface CoachInput {
  // 现有字段
  event_type: 'dialogue_turn' | 'silence_timeout' | 'wake_request'
  session_id: string
  user_id: string
  npc_id: string
  timestamp: number

  // dialogue_turn 专属
  player_text?: string
  npc_response?: string
  language?: string

  // silence_timeout 专属
  silence_ms?: number

  // 新增字段（可选，向后兼容）
  player_level?: 'A1' | 'A2' | 'B1' | 'B2'  // 默认 'A1'
  recent_turns?: Array<{                      // 默认 []
    speaker: 'player' | 'npc'
    text: string
  }>
}
```

### 3.2 LLM 输出（语义内容）

```typescript
// LLM 返回的语义内容（服务端填充元数据）
interface CoachResponse {
  text: string              // 给玩家的提示文本
  emotion: 'encourage' | 'neutral' | 'celebrate'
  repeat_phrase?: string    // 让玩家重复的短语（TTS/跟读用）
  should_tts: boolean       // 是否 TTS 朗读
  ttl_ms?: number           // 显示时长（默认 8000）
}
```

### 3.3 最终输出（服务端组装）

```typescript
// CoachIntervention（服务端填充元数据后）
interface CoachIntervention {
  event_id: string          // UUID v4（服务端生成）
  session_id: string        // 从输入取
  user_id: string           // 从输入取
  trigger: 'wake' | 'error' | 'silence'  // 从 TriggerClassifier 取
  priority: 1 | 2 | 3       // silence=1, error=2, wake=3
  text: string              // 从 LLM 响应取
  repeat_phrase?: string    // 从 LLM 响应取
  emotion: string           // 从 LLM 响应取（'encourage' | 'neutral' | 'celebrate'）
  should_tts: boolean       // 从 LLM 响应取
  ttl_ms: number            // 从 LLM 响应取（默认 8000）
  timestamp: number         // Date.now()（服务端生成）
}
```

> **客户端兼容性注意**：`emotion` 新增了 `celebrate` 值（连续正确时表扬）。
> 当前客户端 CoachOverlay 只处理 `encourage` 和 `neutral`。
> 新增 `celebrate` 需要客户端配套更新（例如显示星星/烟花特效），否则 fallback 为 `encourage` 的视觉效果即可。

### 3.4 处理流程

```
1. Redis Stream 读取 coach.input 消息
2. Zod 验证 schema（player_level 默认 'A1'，recent_turns 默认 []）
3. TriggerClassifier 分类 trigger（wake/silence/error）
4. InterventionPolicy 检查冷却策略
5. 如果需要干预：
   a. ContextAssembler 提取上下文（player_level, recent_turns）
   b. PromptBuilder 组装 prompt（基础 + 动态注入）
   c. LLMCoach 调用 LLM（5s 超时）
   d. 如果成功：解析 LLM 响应，组装 CoachIntervention
   e. 如果失败：使用 fallback 模板
6. 输出到 Redis Stream（coach.intervention）+ WebSocket
```

---

## 4. Prompt 设计

### 4.1 文件结构

```
services/spirit-coach-service/
  prompts/
    system.txt          # 基础 prompt（小飞猫人设、通用规则、输出格式）
    context-error.txt   # error 触发时的动态注入模板
    context-silence.txt # silence 触发时的动态注入模板
    context-wake.txt    # wake 触发时的动态注入模板
```

### 4.2 基础 Prompt（prompts/system.txt）

```
你是小飞猫（Xiao Fei Mao），一个友善、有趣的英语教练。你的任务是帮助中国小学生学习英语。

## 人设
- 你是一只可爱的小猫，说话带"喵~"
- 你友善、耐心、鼓励性强
- 你用中英双语交流，根据学生等级调整比例

## 语言比例规则
- A1 等级：90% 中文 + 10% 英文
- A2 等级：50% 中文 + 50% 英文
- B1 等级：30% 中文 + 70% 英文
- B2 等级：20% 中文 + 80% 英文

## 输出格式
你必须返回 JSON，包含以下字段：
{
  "text": "给玩家的提示文本（30-300 字符）",
  "emotion": "encourage | neutral | celebrate",
  "repeat_phrase": "让玩家重复的短语（可选）",
  "should_tts": true/false,
  "ttl_ms": 8000
}

## 通用规则
- 永远不要批评或负面评价玩家
- 错误纠正时，先肯定再纠正
- 沉默鼓励时，提供具体的建议（例如"试试说..."）
- 保持简短（30-300 字符）
```

### 4.3 动态注入模板

**context-error.txt**：
```
## 当前场景
玩家在和 NPC 对话时说了一句英语，但有错误。

## 玩家信息
- 等级：{{player_level}}
- 玩家说：{{player_text}}
- NPC 回应：{{npc_response}}
{{#if recent_turns}}
- 最近对话：
{{#each recent_turns}}
  - {{speaker}}: {{text}}
{{/each}}
{{/if}}
{{#if error_streak}}
- 连续错误：{{error_streak}} 次（请降低难度、多鼓励）
{{/if}}
{{#if correct_streak}}
- 连续正确：{{correct_streak}} 次（请表扬、可能提升挑战）
{{/if}}

## 任务
1. 检测玩家句子里的错误（语法、词汇、语用）
2. 用友善的方式纠正错误
3. 提供正确的说法
4. 鼓励玩家再试一次
```

**context-silence.txt**：
```
## 当前场景
玩家已经沉默了 {{silence_ms}} 毫秒，可能需要鼓励。

## 玩家信息
- 等级：{{player_level}}
{{#if recent_turns}}
- 最近对话：
{{#each recent_turns}}
  - {{speaker}}: {{text}}
{{/each}}
{{/if}}

## 任务
1. 鼓励玩家开口说英语
2. 提供一个简单的建议（例如"试试说...")
3. 保持友善、耐心
```

**context-wake.txt**：
```
## 当前场景
玩家主动呼唤你求助。

## 玩家信息
- 等级：{{player_level}}
- 玩家说：{{player_text}}
{{#if recent_turns}}
- 最近对话：
{{#each recent_turns}}
  - {{speaker}}: {{text}}
{{/each}}
{{/if}}

## 任务
1. 回应玩家的求助
2. 提供帮助或建议
3. 保持友善、鼓励
```

### 4.4 Prompt 组装逻辑

`buildPrompt` 返回两个独立字符串：system prompt 和 user prompt。

```typescript
async function buildPrompts(
  trigger: 'wake' | 'error' | 'silence',
  input: CoachInput
): Promise<{ system: string; user: string }> {
  // 1. 读取基础 prompt（system 角色）
  const systemPrompt = await readFile('prompts/system.txt', 'utf-8')

  // 2. 读取动态注入模板（user 角色）
  const contextTemplate = await readFile(`prompts/context-${trigger}.txt`, 'utf-8')

  // 3. 准备模板变量
  const variables = {
    player_level: input.player_level || 'A1',
    player_text: input.player_text || '',
    npc_response: input.npc_response || '',
    silence_ms: input.silence_ms || 0,
    recent_turns: input.recent_turns || [],
    // Phase 2 添加：
    // error_streak: streakTracker.getErrorStreak(input.user_id),
    // correct_streak: streakTracker.getCorrectStreak(input.user_id),
  }

  // 4. 渲染模板（使用 Handlebars 或简单字符串替换）
  const contextPrompt = renderTemplate(contextTemplate, variables)

  return { system: systemPrompt, user: contextPrompt }
}
```

LLM 调用：

```typescript
const { system, user } = await buildPrompts(trigger, input)
const response = await this.openai.chat.completions.create({
  model: this.model,
  messages: [
    { role: 'system', content: system },  // system.txt（人设 + 规则）
    { role: 'user', content: user }       // context-*.txt（场景描述）
  ],
  // ...
})
```

---

## 5. 客户端设计

### 5.1 CoachContextTracker（新增类）

客户端需要维护一个滑动窗口，跟踪最近的对话轮次。

```gdscript
# res://scripts/coach/CoachContextTracker.gd
class_name CoachContextTracker
extends RefCounted

const MAX_TURNS = 5

var _turns: Array[Dictionary] = []

func add_turn(speaker: String, text: String) -> void:
    _turns.append({
        "speaker": speaker,
        "text": text
    })
    # 保持最多 MAX_TURNS 轮
    if _turns.size() > MAX_TURNS * 2:  # *2 因为 player+npc 各一条
        _turns = _turns.slice(_turns.size() - MAX_TURNS * 2)

func get_recent_turns() -> Array[Dictionary]:
    return _turns.duplicate()

func clear() -> void:
    _turns.clear()
```

### 5.2 集成到 NPC 对话系统

在每个场景的 NPC 对话系统中：

```gdscript
# 在 NPC 对话开始时初始化
var coach_tracker = CoachContextTracker.new()

# 玩家说话时
func on_player_spoke(text: String) -> void:
    coach_tracker.add_turn("player", text)
    # ... 其他逻辑 ...

# NPC 回应时
func on_npc_responded(text: String) -> void:
    coach_tracker.add_turn("npc", text)
    # ... 其他逻辑 ...

# 发送 coach 事件时
func send_coach_event(event_type: String, extra_data: Dictionary) -> void:
    var payload = {
        "event_type": event_type,
        "session_id": session_id,
        "user_id": user_id,
        "npc_id": npc_id,
        "timestamp": Time.get_unix_time_from_system() * 1000,
        "player_level": player_level,  # 从 session 状态读取
        "recent_turns": coach_tracker.get_recent_turns(),
    }
    payload.merge(extra_data)

    # HTTP POST to /api/v1/coach/events
    await http_client.post("/api/v1/coach/events", payload)
```

### 5.3 影响范围

三个场景都需要改动：
- `apps/godot-client/scenes/SpiritForest.tscn`
- `apps/godot-client/scenes/SpellLibrary.tscn`
- `apps/godot-client/scenes/RainbowGarden.tscn`

每个场景的 NPC 对话脚本需要：
1. 初始化 `CoachContextTracker`
2. 在 player/NPC 对话时调用 `add_turn()`
3. 发送 coach 事件时附带 `player_level` 和 `recent_turns`

---

## 6. 服务端设计

### 6.1 LLMCoach 模块

```typescript
// services/llm-coach.ts
import OpenAI from 'openai'
import { readFile } from 'fs/promises'
import { z } from 'zod'

const CoachResponseSchema = z.object({
  text: z.string().min(30).max(300),
  emotion: z.enum(['encourage', 'neutral', 'celebrate']),
  repeat_phrase: z.string().optional(),
  should_tts: z.boolean(),
  ttl_ms: z.number().default(8000),
})

export class LLMCoach {
  private openai: OpenAI
  private model: string

  constructor() {
    this.openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
    this.model = process.env.COACH_LLM_MODEL || 'gpt-4o-mini'
  }

  async generate(input: CoachInput, trigger: string): Promise<CoachResponse> {
    const { system, user } = await buildPrompts(trigger, input)

    try {
      const response = await this.openai.chat.completions.create({
        model: this.model,
        messages: [
          { role: 'system', content: system },  // system.txt（人设 + 规则）
          { role: 'user', content: user }       // context-*.txt（场景描述）
        ],
        response_format: { type: 'json_object' },
        temperature: 0.7,
        max_tokens: 300,
      })

      const content = response.choices[0]?.message?.content
      if (!content) throw new Error('Empty LLM response')

      const parsed = JSON.parse(content)
      return CoachResponseSchema.parse(parsed)
    } catch (error) {
      console.error('LLM call failed:', error)
      throw error  // 上层 catch 并使用 fallback
    }
  }
}
```

### 6.2 Fallback 模板

```typescript
// services/fallback-templates.ts
export const FALLBACK_TEMPLATES = {
  wake: {
    text: '喵~ 小飞猫来啦！有什么可以帮你的吗？',
    emotion: 'encourage' as const,
    should_tts: true,
    ttl_ms: 8000,
  },
  silence: {
    text: '喵~ 想不出来也没关系，慢慢来！',
    emotion: 'encourage' as const,
    should_tts: true,
    ttl_ms: 8000,
  },
  error: {
    text: '喵~ 差一点点，再试一次！',
    emotion: 'encourage' as const,
    should_tts: true,
    ttl_ms: 8000,
  },
}
```

### 6.3 CoachInputConsumer 集成

```typescript
// workers/coach-input-consumer.ts（修改）
import { LLMCoach } from '../services/llm-coach'
import { FALLBACK_TEMPLATES } from '../services/fallback-templates'

export class CoachInputConsumer {
  private llmCoach: LLMCoach

  constructor() {
    this.llmCoach = new LLMCoach()
  }

  async consumeOnce(): Promise<void> {
    // ... 现有逻辑（读取 Redis、验证、分类、策略检查）...

    if (shouldIntervene) {
      try {
        // 调用 LLM（5s 超时）
        const llmResponse = await Promise.race([
          this.llmCoach.generate(input, trigger),
          new Promise((_, reject) =>
            setTimeout(() => reject(new Error('LLM timeout')), 5000)
          )
        ])

        // 组装 CoachIntervention
        const intervention: CoachIntervention = {
          event_id: uuidv4(),
          session_id: input.session_id,
          user_id: input.user_id,
          trigger,
          priority: trigger === 'silence' ? 1 : trigger === 'error' ? 2 : 3,
          text: llmResponse.text,
          repeat_phrase: llmResponse.repeat_phrase,
          emotion: llmResponse.emotion,
          should_tts: llmResponse.should_tts,
          ttl_ms: llmResponse.ttl_ms || 8000,
          timestamp: Date.now(),
        }

        // 输出到 Redis Stream + WebSocket
        await this.outputIntervention(intervention)
      } catch (error) {
        // LLM 失败，使用 fallback
        console.error('LLM failed, using fallback:', error)
        const fallback = FALLBACK_TEMPLATES[trigger]
        const intervention: CoachIntervention = {
          event_id: uuidv4(),
          session_id: input.session_id,
          user_id: input.user_id,
          trigger,
          priority: trigger === 'silence' ? 1 : trigger === 'error' ? 2 : 3,
          text: fallback.text,
          emotion: fallback.emotion,
          should_tts: fallback.should_tts,
          ttl_ms: fallback.ttl_ms,
          timestamp: Date.now(),
        }
        await this.outputIntervention(intervention)
      }
    }
  }
}
```

---

## 7. 测试策略

### 7.1 MVP（Phase 1）— Schema 测试

验证 LLM 输出符合 schema：

```typescript
// __tests__/llm-coach.test.ts
import { LLMCoach } from '../services/llm-coach'

describe('LLMCoach', () => {
  it('output matches CoachResponse schema', async () => {
    const coach = new LLMCoach()
    const output = await coach.generate(
      {
        event_type: 'dialogue_turn',
        session_id: 'test',
        user_id: 'test',
        npc_id: 'test',
        player_text: 'I am go to school',
        player_level: 'A1',
        timestamp: Date.now(),
      },
      'error'
    )

    expect(output).toHaveProperty('text')
    expect(output).toHaveProperty('emotion')
    expect(['encourage', 'neutral', 'celebrate']).toContain(output.emotion)
    expect(output.text.length).toBeGreaterThanOrEqual(30)
    expect(output.text.length).toBeLessThanOrEqual(300)
    expect(typeof output.should_tts).toBe('boolean')
  })
})
```

### 7.2 Phase 2 — 集成测试

10 个典型场景测试：

```typescript
describe('LLMCoach integration', () => {
  it('A1 player says "I am go" → correction', async () => {
    const output = await coach.generate(
      { player_text: 'I am go to school', player_level: 'A1', ... },
      'error'
    )
    expect(output.text).toMatch(/go|going/i)
    expect(output.emotion).toBe('encourage')
  })

  it('A1 player silent 15s → Chinese encouragement', async () => {
    const output = await coach.generate(
      { silence_ms: 15000, player_level: 'A1', ... },
      'silence'
    )
    expect(output.text).toMatch(/[一-龥]/)  // 包含中文
    expect(output.emotion).toBe('encourage')
  })

  // ... 其他 8 个场景 ...
})
```

---

## 8. 分阶段计划

### Phase 1（MVP）— 核心功能

**范围**：
- ✅ LLM 单次调用替换 ErrorDetector + CoachHintGenerator
- ✅ 单一 prompt + 动态注入（trigger + player_level）
- ✅ 可配置 LLM 模型（默认 GPT-4o-mini，环境变量 `COACH_LLM_MODEL`）
- ✅ 客户端上报 player_level + recent_turns
- ✅ 5s 超时 + fallback 模板
- ✅ Schema 测试

**不包含**：
- ❌ Streak tracking（Phase 2）
- ❌ 集成测试（Phase 2）
- ❌ LLM-as-judge 质量评估（Phase 3）

**预估工作量**：3-5 天

### Phase 2 — 增强

**范围**：
- Streak tracking 接入（抽离独立模块）
- Prompt 动态注入 streak 数据
- 集成测试（10 个场景）

**预估工作量**：2-3 天

### Phase 3 — 优化

**范围**：
- LLM-as-judge 质量评估
- A/B 测试框架
- 监控告警（fallback 频率、延迟分布、成本追踪）
- Prompt 缓存优化（避免每次 readFile）

**预估工作量**：5-7 天

---

## 9. 向后兼容

### 9.1 Schema 变更

`coach.input` event schema 新增字段（可选）：

```typescript
const CoachInputSchema = z.object({
  // ...现有字段...
  player_level: z.enum(['A1', 'A2', 'B1', 'B2']).default('A1'),
  recent_turns: z.array(z.object({
    speaker: z.enum(['player', 'npc']),
    text: z.string()
  })).default([])
})
```

### 9.2 迁移策略

- **旧客户端**：缺少 `player_level` 和 `recent_turns`，使用默认值（'A1', []）
- **新客户端**：上报真实数据，LLM 教练体验更好
- **部署顺序**：先部署 coach-service（后端），再发布客户端更新（前端）

---

## 10. 成本估算

### 10.1 单次调用

- System prompt: ~300 tokens
- Context injection: ~200 tokens
- Conversation history (5 turns): ~500-1000 tokens
- Output: ~100-200 tokens
- **总计**: ~1100-1700 tokens/次

### 10.2 日均成本

假设：
- 1000 活跃用户
- 每用户每天 3 个 session
- 每 session 10 次教练触发
- 总计：30,000 次/天

GPT-4o-mini 价格：
- Input: $0.15/M tokens
- Output: $0.60/M tokens

**日均成本**：~$6/天，~$180/月

---

## 11. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| LLM 延迟过高（>5s） | UX 差 | 5s 超时 + fallback 模板 |
| LLM 输出质量差 | 玩家体验差 | Schema 测试 + 集成测试 + 人工抽检 |
| LLM API 故障 | 完全无教练 | Fallback 模板兜底 |
| 成本超预期 | 财务风险 | 监控调用次数，必要时降级到更便宜模型 |
| Prompt 被滥用 | 不当输出 | 输入过滤 + 输出过滤 |

---

## 12. 成功标准

MVP 上线后，验证以下指标：

1. **功能正确性**：LLM 教练能正确检测错误并生成纠正响应
2. **响应质量**：响应符合小飞猫人设，友善、鼓励、有趣
3. **延迟可接受**：95% 的响应在 3s 内完成
4. **Fallback 频率低**：<5% 的调用走 fallback
5. **成本可控**：日均成本 <$10

---

## 13. 附录

### 13.1 相关文件

- `services/spirit-coach-service/src/services/error-detector.ts` — 部分修改（保留触发器分类，移除纠正文本生成）
- `services/spirit-coach-service/src/services/coach-hint-generator.ts` — 退役（被 LLM 替换）
- `services/spirit-coach-service/src/workers/coach-input-consumer.ts` — 修改（集成 LLM）
- `services/spirit-coach-service/src/services/llm-coach.ts` — 新增
- `services/spirit-coach-service/src/services/prompt-builder.ts` — 新增
- `services/spirit-coach-service/src/services/context-assembler.ts` — 新增
- `services/spirit-coach-service/src/services/fallback-templates.ts` — 新增
- `services/spirit-coach-service/prompts/` — 新增（system.txt + context-*.txt）
- `apps/godot-client/scripts/coach/CoachContextTracker.gd` — 新增

### 13.2 参考资料

- [OpenAI API 文档](https://platform.openai.com/docs)
- [GPT-4o-mini 模型卡片](https://platform.openai.com/docs/models/gpt-4o-mini)
- [小飞猫人设文档](./spirit-character.md)（待补充）
