# 精灵教练 Agent MVP 设计

## 背景

精灵教练 Agent 是语言学习 RPG 中的旁路教学伙伴。它不替代 NPC 主对话流，而是在玩家出现严重语言错误、长时间沉默或主动求助时，提供即时、鼓励式的学习提示。

MVP 目标是先完成一个稳定闭环：系统能感知触发事件，精灵能实时出现，玩家能看到或听到一句可执行的帮助。长期学习画像、复杂个性化和家长报告留到后续阶段。

## 目标

- 支持三类 MVP 触发：严重错误、沉默 15 秒、主动求助。
- 通过独立 `spirit-coach-service` 做触发分类、介入决策和提示生成。
- 通过 Redis Streams 解耦主对话和教练链路。
- 通过 `/ws/coach` 将教练提示实时推送到 Godot。
- 使用现有 `CoachOverlay` 展示精灵气泡，可选 TTS 播报。
- 保证教练链路失败时，NPC 主对话仍然继续。

## 非目标

- 不做长期学习画像或完整错题本。
- 不做周报、家长控制台汇总或多端同步。
- 不让 LLM 决定是否打断孩子。
- 不做离线补发；WebSocket 不在线时跳过实时提示。
- 不新增大型教练 UI，只复用现有精灵气泡。

## 总体架构

```text
Godot VoicePipeline / DialogueManager
        │
        │ 玩家说话 / 沉默 / 唤醒求助
        ▼
voice-service / dialogue-service
        │
        │ 写入 Redis Stream: coach.input
        ▼
spirit-coach-service
        │
        ├─ ErrorDetector：严重错误检测
        ├─ TriggerClassifier：区分 error / silence / wake
        ├─ InterventionPolicy：冷却、优先级、是否介入
        ├─ CoachHintGenerator：生成鼓励式提示
        └─ CoachSessionManager：管理 WebSocket 在线连接
        │
        │ 写入 Redis Stream: coach.intervention
        │ 通过 /ws/coach 推送给在线 Godot 客户端
        ▼
Godot CoachOverlay + AudioManager
        │
        └─ 显示 Spark 提示气泡，必要时调用 TTS 播报
```

核心原则：精灵教练永远旁路运行，不阻塞主对话。主对话链路负责 ASR、NPC 回复、TTS 和继续监听；教练链路负责额外提示。

## 事件协议

### `coach.input`

`coach.input` 是进入精灵教练的统一输入流。

#### 对话回合事件

```json
{
  "event_type": "dialogue_turn",
  "session_id": "session-123",
  "user_id": "user-123",
  "npc_id": "merchant-001",
  "player_text": "I am go to school",
  "npc_response": "...",
  "language": "en",
  "timestamp": 1779177600000
}
```

#### 沉默事件

```json
{
  "event_type": "silence_timeout",
  "session_id": "session-123",
  "user_id": "user-123",
  "npc_id": "merchant-001",
  "silence_ms": 15000,
  "timestamp": 1779177600000
}
```

#### 主动求助事件

```json
{
  "event_type": "wake_request",
  "session_id": "session-123",
  "user_id": "user-123",
  "npc_id": "merchant-001",
  "player_text": "help me",
  "timestamp": 1779177600000
}
```

### `coach.intervention`

`coach.intervention` 是精灵教练生成的输出流，也作为 WebSocket 推送 payload。

```json
{
  "event_id": "coach-event-123",
  "session_id": "session-123",
  "user_id": "user-123",
  "trigger": "error",
  "priority": 2,
  "text": "差一点点！可以说：I am going.",
  "repeat_phrase": "I am going.",
  "emotion": "encourage",
  "should_tts": true,
  "ttl_ms": 8000,
  "timestamp": 1779177600000
}
```

字段约定：

- `trigger`: `wake`、`error`、`silence`。
- `priority`: `wake` 高于 `error`，`error` 高于 `silence`。
- `text`: Godot 气泡展示文本，中文为主，包含一个可重复英文短句。
- `repeat_phrase`: 可选跟读短句。
- `emotion`: 映射到 `CoachOverlay.show_hint(text, emotion)`。
- `should_tts`: 是否调用现有 TTS 播放。
- `ttl_ms`: Godot 自动隐藏提示的建议时长。

## 服务内部组件

建议在 `services/spirit-coach-service/src` 中拆分为以下组件：

```text
routes/
  coach.ts
  coach-ws.ts
workers/
  coach-input-consumer.ts
services/
  trigger-classifier.ts
  error-detector.ts
  intervention-policy.ts
  coach-hint-generator.ts
  coach-session-manager.ts
```

### `coach-input-consumer.ts`

从 Redis Stream `coach.input` 读取事件，负责反序列化、校验和调用后续服务。不在 worker 中承载复杂业务规则。

### `trigger-classifier.ts`

统一分类输入事件：

- `dialogue_turn`：调用 `ErrorDetector`，只有 high severity 进入 `error` 触发。
- `silence_timeout`：识别为 `silence` 触发，事件由上游在沉默 15 秒时产生。
- `wake_request`：识别为 `wake` 触发。

### `intervention-policy.ts`

决定是否介入：

- `wake`：最高优先级，绕过冷却。
- `error`：只对 high severity 介入，并走冷却。
- `silence`：15 秒后触发，但走冷却。

冷却 key 建议：

```text
cooldown:{user_id}:spirit:error
cooldown:{user_id}:spirit:silence
```

如果同一时间存在多个候选触发，优先级为：`wake > error > silence`。

### `coach-hint-generator.ts`

MVP 使用规则模板生成提示，不接 LLM。

示例模板：

- error: `差一点点！可以说：“I am going.” 跟我读一遍：I am going.`
- silence: `想不出来也没关系，可以试试说：“I need help.”`
- wake: `我来帮你！你可以说：“Can you help me?”`

提示风格以中文解释为主，并包含一个可重复的英文短句。

### `coach-session-manager.ts`

管理 Godot WebSocket 在线连接，按 `session_id` 或 `user_id` 查找客户端。

生成 intervention 后：

1. 写入 `coach.intervention`。
2. 如果客户端在线，通过 `/ws/coach` 推送。
3. 如果客户端不在线，只保留事件，不阻塞主流程。

## Godot 集成

Godot 侧需要接收 `/ws/coach` 消息并映射到现有展示能力：

```text
coach intervention received
        │
        ├─ CoachOverlay.show_hint(text, emotion)
        ├─ should_tts=true 时调用现有 TTS
        └─ ttl_ms 到期后隐藏气泡
```

展示层不改变 NPC 主对话状态机。教练提示应作为覆盖层出现，不暂停 NPC 对话，不阻止后续语音监听。

沉默事件应以 15 秒为阈值产生。若玩家在 15 秒内重新说话，则不发送 `silence_timeout`。

主动求助可以先支持少量规则表达，例如 `help`、`help me`、`帮帮我`、`我不会`。这些表达进入 `wake_request`，优先响应。

## 数据流

1. Godot 捕获玩家语音、沉默或求助。
2. voice-service / dialogue-service 处理主对话。
3. dialogue-service 对每次对话回合写入 `coach.input`。
4. Godot 或后端在沉默 15 秒、主动求助时写入 `coach.input`。
5. `spirit-coach-service` 消费 `coach.input`。
6. 服务分类触发、检查冷却、生成提示。
7. 服务写入 `coach.intervention`。
8. 服务通过 `/ws/coach` 推送在线 Godot 客户端。
9. Godot 显示精灵气泡，并在需要时播放 TTS。

## 错误处理与降级

教练失败时静默降级，主对话继续。

- Redis 写入失败：记录错误，不阻塞 NPC 回复。
- 单条事件处理失败：记录错误，不让 worker 整体退出。
- 坏消息处理：MVP 可删除异常事件，避免无限循环。
- WebSocket 推送失败：跳过实时推送，保留 `coach.intervention` 事件。
- TTS 播放失败：仍显示文字气泡，不影响 NPC TTS 或监听。
- 冷却检查失败：默认不介入，避免频繁打断儿童体验。

## 测试策略

### 单元测试

覆盖以下组件：

- `TriggerClassifier`
- `InterventionPolicy`
- `CoachHintGenerator`

重点断言：

- `wake` 优先级最高。
- `wake` 绕过冷却。
- `error` 需要 high severity 才介入。
- `error` 和 `silence` 走冷却。
- `silence_timeout` 使用 15 秒语义。
- 提示文本包含中文解释和一个英文短句。

### 服务集成测试

写入一条 `coach.input`，验证 worker 消费后生成 `coach.intervention`，并检查 payload 字段完整。

### Godot 手动验收

- 玩家说出高严重度错误句子，精灵显示纠错提示。
- 玩家沉默 15 秒，精灵显示鼓励提示。
- 玩家说 `help` 或 `帮帮我`，精灵立即响应。
- 断开 coach-service 后，NPC 对话仍可继续。

## 后续扩展

- 学习画像：统计高频错误、掌握词汇和需要复习的句型。
- LLM 教练生成：保留 `CoachHintGenerator` 接口，后续替换规则模板。
- 任务系统联动：根据当前任务目标生成更具体提示。
- 家长控制台：汇总本周常见错误和已掌握表达。
- 表情与语音增强：按 `emotion` 切换精灵动画，对 `repeat_phrase` 使用更清晰的跟读语音。
