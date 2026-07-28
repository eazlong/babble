# 委托意图交由前端完成，voice-service 保持无状态

## 状态

accepted

## 背景

voice-service 的 `ASRPostprocessor`（`services/voice-service/src/services/asr_postprocess.py`）负责对 ASR 文本做无状态变换：纠错、抽取预期槽位、判断 `intent_matched`、最多生成一句确认追问。其 system prompt 明确禁止 `Do not invent slot values when intent is not matched.`，且整个服务是单次 HTTP 调用——跨轮上下文靠客户端每轮重传 `recent_turns` 重建。

当 NPC 询问玩家英文名、玩家回答"你帮我起一个吧"时，玩家并非填值，而是把填写权委托回 NPC。这要求系统识别出"委托"意图，并由 NPC 从一个受控值池里挑值、拼出推荐语（如"那就叫 Wendy，你觉得怎么样？"）、再推进"提议→确认"的跨轮状态。当前契约做不到：post-processor 被禁止造值，且不持有跨轮状态。

## 决策

**识别在 voice-service，完成在前端。** voice-service 保持无状态变换器的定位，只新增一个意图输出；值池、挑选策略、推荐语、槽位状态机全部由前端持有与推进。

具体安排：

1. **意图输出升级**：post-processor 输出从布尔 `intent_matched` 升级为枚举 `intent: "provide" | "delegate" | "off_topic"`（保留 `intent_matched` 作向后兼容，等价于 `intent === "provide"`）。`delegate` 即委托信号；`off_topic` 统一覆盖跑题与不构成回答的情形。澄清拼写仍由现有 `guidance`/`_looks_like_confirmation` 通道处理，不单列状态。

2. **值池由前端传入**：每个可委托槽位的值池、挑选策略、是否可委托，作为 `ExpectedSlot` 的扩展字段随请求传入。voice-service 透传这些字段、仅读取判意图所需部分，不解释值池、不触碰游戏内容。封闭题的 `candidate_answers` 视为值池的一个特例。

3. **前端完成器与状态机**：前端为每个槽位维护三态机 `AWAITING → PROPOSED(value) → FILLED`。收到 `delegate` 即跑完成器 `pool → pick(strategy, exclude_recent) → propose`，用槽位配置里的模板拼推荐语（如"那就叫{value}，你觉得怎么样？"）。PROPOSED 下若 voice-service 返回 `extracted[key]` 非空即落定为最终值（接受提议回填提议值，拒绝另给则回填玩家新值），无需新增 `accepted_proposal` 字段。PROPOSED 下再次 `delegate` 视为"再换一个"，排除已提议值后重新挑选。

4. **推荐语默认模板、可选 LLM 润色**：完成器默认用槽位配置中的静态模板拼推荐语（可控、可测、零延迟、零 token）。如需更生动话术，槽位可携带 `propose_prompt` 交由 dialogue-service 的 LLM 润色，但这是可选增强，完成器不依赖 dialogue-service。

5. **本期范围**：仅覆盖"有值池的委托"。无值池、需 LLM 现场生成的委托（如"给我讲个故事开头"）本期不做，仍走普通对话路径。

## 考虑过的选项

- **A. 放松 voice-service 契约，让 post-processor 自己造值 + 出推荐语。** 否决：会把游戏内容（名字池、推荐策略）渗入语音服务，违反服务边界；名字由 LLM 随机出，不可控、不可复现，儿童产品有合规风险；post-processor 不持有跨轮状态，无法保证"不重复推荐上次提议的值"。

- **B. 把状态机放进 voice-service（加 session 存储）。** 否决：值池已在前端，把"持值池的层"与"持状态的层"劈成两半反而更碎；voice-service 的无状态、可水平扩展、双客户端（Godot + Cocos）复用等特性会被破坏。现有 `recent_turns` 已是"前端重建上下文"的同构模式，状态机是它的自然延伸。

## 后果

- voice-service 这一侧改动极小：仅扩展 post-processor 输出为意图枚举，不引入状态、不引入游戏内容、不破坏现有 `guidance` 通道。
- 前端承担完成器 + 三态机 + 值池协议的落地工作；这是路线 B 的主要实现成本所在。
- 通用化以"每个可委托槽位绑定一个值池"为统一模型：封闭题与开放题共用同一套 `pick → propose` 完成器，差异仅在值池内容与挑选策略。
- 无值池的生成式委托被显式排除在本期之外，未来若需要应作为独立委托类型扩展，而非塞回当前模型。
