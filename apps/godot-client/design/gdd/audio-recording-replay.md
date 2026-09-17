# 录音保存与结构化回放规划

## Overview

本系统把玩家的语音学习过程记录为“言灵回声”：每次孩子用英语回应 NPC 或 飞飞，系统保存必要的短录音、结构化事件、ASR、评分摘要和反馈结果，用于即时游戏反馈、家长成长回顾、后续个性化练习。

核心目标不是收集证据，而是让“语言即言灵钥匙”可追溯：孩子说出的英语触发了什么言灵回应、飞飞 怎样鼓励、玩家如何从需要帮助逐步变得更熟练。

## Player Fantasy

玩家应该感觉：“我说出的英语会留下言灵回声，飞飞 记得我的成长。”

设计原则：

- **言灵回声**：录音不是考试证据，而是孩子施法过程留下的短暂回响。
- **成长回顾**：家长看到的是努力、尝试、进步，不是错题审判。
- **无失败惩罚**：系统内部可记录状态，但面向孩子和家长不使用“失败次数”作为核心叙事。
- **飞飞 陪伴**：录音不清、上传等待、评分延迟，都由 飞飞 用温柔语气解释。
- **隐私优先**：儿童语音和 ASR 原文是高敏感数据，默认最小化采集、可删除、可撤回同意。

## MVP Definition

### Planning MVP

当前阶段只交付规划文档，不开发功能。

Planning MVP 验收目标：

- 定义领域模型、状态机、权限边界、隐私策略、音频规则、失败场景、验收标准。
- 明确哪些能力属于后续 Implementation MVP。
- 避免在文档层留下会固化为实现债务的矛盾设计。

### Implementation MVP（后续开发范围）

若进入开发，Implementation MVP 优先包含：

1. `GameSession` / `PromptTurn` / `InteractionAttempt` / `AudioRecording` / `TimelineEvent` 数据模型。
2. Godot 客户端本地短录音保存。
3. 本地待补传队列。
4. 后端对象存储上传。
5. 私有对象存储 key 元数据。
6. 学习关键事件时间线。
7. 录音删除时保留时间线、删除敏感证据。
8. 家长端基础成长回顾。

Implementation MVP 不包含：

- 屏幕录像回放。
- 整局连续录音。
- 孩子端完整历史回放。
- 教研后台原始录音浏览。
- 多段长回答录音。
- 下载原始录音。

## Experience Semantics

同一底层状态在不同受众中使用不同语言。

| 系统层状态 | 儿童端表达 | 家长端表达 | 避免用语 |
|---|---|---|---|
| `attempt_completed` | 言灵回应已记录 | 完成一次表达 | 失败 / 错误提交 |
| `needs_support` | 飞飞 来帮忙 | 需要提示后继续 | 失败次数 |
| `asr_unclear` | 飞飞 没听清 | 本次识别不清晰 | 识别失败导致错误 |
| `magic_activated` | 言灵被点亮 | 表达已达成目标 | 通过考试 |
| `recording_pending_upload` | 言灵回声同步中 | 录音同步中 | 上传失败 |
| `recording_deleted` | 回声已被清除 | 录音已删除 | 证据丢失 |
| `deep_assessment_pending` | 飞飞 正在整理成长记录 | 深度分析处理中 | 评分失败 |

内部代码可以使用准确状态名，但 UI、家长报告、飞飞 文案必须使用正向、支持性语言。

## Domain Model

### GameSession

玩家从进入一个可学习场景到离开该场景之间形成的学习过程单元。

| 字段 | 类型 | 说明 |
|---|---|---|
| `game_session_id` | UUID | 主键 |
| `child_id` | UUID | 孩子 ID |
| `client_session_id` | UUID | 客户端本地会话 ID，幂等用 |
| `scene_id` | string | `spirit_forest` / `spell_library` / `rainbow_garden` |
| `status` | enum | `active` / `ended` / `abandoned` / `expired` |
| `started_at` | timestamp | 服务端创建时间 |
| `last_seen_at` | timestamp | 心跳或事件最后到达时间 |
| `ended_at` | timestamp nullable | 结束时间 |
| `end_reason` | enum nullable | `scene_exit` / `main_menu` / `crash_recovered` / `timeout` |

约束：

- `UNIQUE(child_id, client_session_id)`。
- 默认同一 `child_id` 只允许一个 `active` 学习会话。新学习场景开始时，服务端关闭旧 active session。

### PromptTurn

一次 NPC 或系统发起的教学提示或问题。

| 字段 | 类型 | 说明 |
|---|---|---|
| `prompt_turn_id` | UUID | 主键 |
| `game_session_id` | UUID | 外键 |
| `child_id` | UUID | 孩子 ID |
| `scene_id` | string | 场景 |
| `quest_id` | string | 任务 |
| `content_id` | string | 内容 ID |
| `content_version` | int | 内容版本 |
| `prompt_text_snapshot` | string | 当时 NPC/飞飞 提示文本 |
| `target_utterance_snapshot` | string nullable | 目标词句 |
| `expected_answer_type` | enum | `repeat_sentence` / `short_answer` / `describe` / `free_response` |
| `assessment_rule_version` | string | 评分规则版本 |
| `created_at` | timestamp | 创建时间 |

规则：

- 必须保存内容快照，不能只引用当前内容表。
- 自由回答任务中，孩子原话不得写入 `PromptTurn`。

### InteractionAttempt

玩家对一个 `PromptTurn` 的一次回应尝试。它是录音、ASR、评分、回放的核心绑定点。

| 字段 | 类型 | 说明 |
|---|---|---|
| `interaction_attempt_id` | UUID | 主键 |
| `child_id` | UUID | 孩子 ID |
| `game_session_id` | UUID | 外键 |
| `prompt_turn_id` | UUID | 外键 |
| `local_attempt_id` | UUID | 客户端幂等键 |
| `attempt_index` | int | 同一 PromptTurn 下第几次尝试 |
| `recording_status` | enum | 见状态机 |
| `asr_status` | enum | `not_started` / `pending` / `completed` / `unclear` / `deleted` |
| `realtime_assessment_status` | enum | `not_started` / `completed` / `degraded` |
| `deep_assessment_status` | enum | `not_started` / `waiting_recording` / `pending` / `completed` / `failed` / `recording_unavailable` / `deleted` |
| `created_at` | timestamp | 创建时间 |
| `deleted_sensitive_data_at` | timestamp nullable | 敏感证据清理时间 |

约束：

- `UNIQUE(child_id, local_attempt_id)`。
- `PromptTurn` 1:N `InteractionAttempt`。
- Implementation MVP 中 `InteractionAttempt` 1:0..1 `AudioRecording`。不支持一 attempt 多段录音。

### AudioRecording

一次交互尝试产生的原始录音元数据。

| 字段 | 类型 | 说明 |
|---|---|---|
| `audio_recording_id` | UUID | 主键 |
| `interaction_attempt_id` | UUID | 外键 |
| `child_id` | UUID | 孩子 ID |
| `game_session_id` | UUID | 外键 |
| `prompt_turn_id` | UUID | 外键 |
| `local_recording_id` | UUID | 客户端录音幂等键 |
| `status` | enum | 见状态机 |
| `storage_bucket` | string nullable | 私有 bucket |
| `storage_key` | string nullable | 对象存储 key，不是可播放 URL |
| `canonical_storage_key` | string nullable | 后端转码后的 canonical 音频 |
| `mime_type` | string | 文件 MIME |
| `container` | string | `wav` / `m4a` / `webm` 等 |
| `codec` | string | `pcm_s16le` / `aac` / `opus` 等 |
| `sample_rate_hz` | int | 采样率 |
| `bit_depth` | int nullable | 位深 |
| `channels` | int | 声道数，MVP 目标 mono |
| `duration_ms` | int | 总时长 |
| `speech_duration_ms` | int nullable | 有效语音时长 |
| `file_size_bytes` | int | 文件大小 |
| `checksum_sha256` | string | 完整性校验 |
| `peak_dbfs` | float nullable | 峰值 |
| `estimated_snr_db` | float nullable | 估算信噪比 |
| `quality_flags` | string[] | `clipped` / `low_volume` / `noisy` / `possible_playback_leakage` |
| `vad_start_ms` | int nullable | VAD 起点 |
| `vad_end_ms` | int nullable | VAD 终点 |
| `pre_roll_ms` | int | 预留前缓冲 |
| `post_roll_ms` | int | 预留后缓冲 |
| `created_at` | timestamp | 创建时间 |
| `uploaded_at` | timestamp nullable | 上传成功时间 |
| `deleted_at` | timestamp nullable | 删除时间 |

约束：

- `UNIQUE(interaction_attempt_id)` for Implementation MVP。
- `UNIQUE(child_id, local_recording_id)`。
- 不保存长期可播放 `raw_url`。
- 文件名和 storage key 不包含孩子姓名、目标句、场景文本、评分信息。

对象存储 key：

```text
recordings/{env}/{child_hash}/{yyyy}/{mm}/{audio_recording_id}.{ext}
```

说明：

- `child_hash` 是不可逆哈希或内部派生前缀，不是裸 `child_id`。
- 权限不依赖路径，必须由后端鉴权。
- bucket 必须私有。

### ASRResult

| 字段 | 类型 | 说明 |
|---|---|---|
| `asr_result_id` | UUID | 主键 |
| `interaction_attempt_id` | UUID | 外键 |
| `audio_recording_id` | UUID nullable | 外键 |
| `engine` | string | ASR 引擎 |
| `engine_version` | string | 引擎版本 |
| `status` | enum | `completed` / `unclear` / `failed` / `deleted` |
| `transcript_sensitive` | string nullable | ASR 原文，高敏感 |
| `confidence` | float nullable | 置信度 |
| `word_details_sensitive` | json nullable | 逐词信息，高敏感 |
| `created_at` | timestamp | 创建时间 |
| `deleted_at` | timestamp nullable | 敏感字段删除时间 |

约束：

- `UNIQUE(interaction_attempt_id, audio_recording_id, engine_version)`。
- 删除录音时同步清空 `transcript_sensitive` 和 `word_details_sensitive`。

### AssessmentResult

| 字段 | 类型 | 说明 |
|---|---|---|
| `assessment_result_id` | UUID | 主键 |
| `interaction_attempt_id` | UUID | 外键 |
| `stage` | enum | `realtime` / `deep` |
| `rule_version` | string | 规则版本 |
| `status` | enum | `pending` / `completed` / `degraded` / `failed` / `deleted` |
| `summary_score` | int nullable | 汇总分 |
| `score_bucket` | string nullable | 脱敏分段 |
| `learning_tags` | string[] | 脱敏学习标签 |
| `details_sensitive` | json nullable | 详细错误/发音证据，高敏感 |
| `input_snapshot_hash` | string | 输入快照 hash |
| `created_at` | timestamp | 创建时间 |
| `deleted_at` | timestamp nullable | 敏感字段删除时间 |

约束：

- `UNIQUE(interaction_attempt_id, stage, rule_version)`。
- 深评分不得撤销实时奖励，只能影响长期报告和个性化。

### TimelineEvent

| 字段 | 类型 | 说明 |
|---|---|---|
| `timeline_event_id` | UUID | 主键 |
| `game_session_id` | UUID | 外键 |
| `child_id` | UUID | 孩子 ID |
| `event_type` | enum | 学习关键事件 |
| `sequence_no` | int | 客户端会话内单调递增 |
| `client_occurred_at` | timestamp | 客户端发生时间 |
| `server_received_at` | timestamp | 服务端接收时间 |
| `idempotency_key` | string | 幂等键 |
| `related_entity_type` | string nullable | 关联实体类型 |
| `related_entity_id` | UUID nullable | 关联实体 ID |
| `payload_version` | int | payload 版本 |
| `payload_safe` | json | 不含孩子原话的安全 payload |

约束：

- `UNIQUE(game_session_id, sequence_no)`。
- `UNIQUE(game_session_id, idempotency_key)`。
- 回放按 `sequence_no` 排序；离线补传时不得按入库时间重排学习过程。

## Timeline Events

记录学习关键事件，不记录每帧、坐标、完整操作轨迹。

事件类型：

- `session_started`
- `scene_entered`
- `quest_started`
- `prompt_shown`
- `recording_started`
- `recording_completed`
- `no_speech_detected`
- `asr_completed`
- `asr_unclear`
- `spark_encouragement_shown`
- `magic_response_triggered`
- `npc_reacted`
- `feedback_shown`
- `magic_activated`
- `needs_support`
- `reward_granted`
- `spell_echo_saved`
- `recording_upload_pending`
- `recording_uploaded`
- `recording_deleted`
- `scene_exited`
- `session_ended`

不记录：

- 玩家每个坐标变化。
- 每帧动画。
- UI hover/click 细节。
- 非学习相关背景音效。
- 孩子原始回答文本。

## Recording Rules

### 录音边界

Implementation MVP：每个 `InteractionAttempt` 最多一个 `AudioRecording`，不自动拆段。

默认时长窗口：

| 任务类型 | 建议录音窗口 | 硬上限 |
|---|---:|---:|
| 单词跟读 | 3-5 秒 | 8 秒 |
| 短句跟读 | 5-8 秒 | 12 秒 |
| 简短回答 | 8-12 秒 | 20 秒 |
| 自由表达 | 12-20 秒 | 30 秒 |

30 秒规则：

- 25 秒时给 UI 或 飞飞 提示“言灵回声快保存啦”。
- 30 秒时自动停止录音并保存。
- 状态标记 `max_duration_reached`。
- 不在 MVP 中拆分多段。
- 未来如果支持长回答，必须新增 `AudioRecordingSegment` 数据模型和合并评分策略。

### 静音和 VAD

不保存“纯静音音频”，但保留一次 `InteractionAttempt` 和时间线。

规则：

- 客户端 VAD 用于交互体验和录音停止提示。
- 服务端 VAD 用于校验音频边界和质量标签。
- 检测到有效语音时，保留 `pre_roll_ms = 300-500` 和 `post_roll_ms = 500-800`。
- 句中短暂停顿不得裁剪。
- 低于 300ms 的有效语音标记 `too_short`。
- 玩家点击录音后 5-8 秒无语音，标记 `no_speech_detected`。
- `no_speech_detected` 不进入正常评分，但可触发 飞飞 温柔提示。

### 音频格式

MVP canonical 音频标准：

- mono。
- PCM WAV。
- 16-bit。
- 16 kHz minimum，推荐 24 kHz。
- 后端可接收平台原生格式，但必须转为 canonical WAV 供 ASR/深评分使用。
- 家长播放可生成压缩播放代理：`m4a/aac` 或 `webm/opus`。

数据保存：

- `storage_key`：源文件或平台原生上传对象。
- `canonical_storage_key`：ASR/评分使用的 canonical WAV。
- 播放 URL 不长期入库，只由后端鉴权后短期生成。

### 音质标签

必须记录：

- `duration_ms`
- `speech_duration_ms`
- `file_size_bytes`
- `checksum_sha256`
- `peak_dbfs`
- `estimated_snr_db`
- `quality_flags`

质量标签用途：

- ASR/评分可降级。
- 家长报告避免把设备/噪声问题误解成孩子能力问题。
- 个性化系统避免基于低质量音频做过度判断。

### 游戏混音规则

录音期间避免 BGM/SFX/TTS 污染麦克风。

- 录音开始前停止 NPC/TTS。
- BGM duck 到 -18 dB 以下或静音。
- UI 点击音效不得落入 pre-roll。
- 录音结束后恢复场景混音。
- 检测到明显系统音串入时，标记 `possible_playback_leakage`。

## Recording State Machines

### AudioRecording status

```text
local_only
  -> pending_upload
  -> uploading
  -> uploaded
  -> upload_failed
  -> pending_upload
  -> upload_expired
  -> delete_requested
  -> delete_pending_storage
  -> deleted_sensitive_data
  -> delete_failed
```

状态说明：

| 状态 | 含义 | 副作用 |
|---|---|---|
| `local_only` | 本地文件已生成，尚未进入上传 | 本地队列记录必须存在 |
| `pending_upload` | 等待上传 | 可重试 |
| `uploading` | 正在上传 | 需要上传锁和超时恢复 |
| `uploaded` | 对象存储成功，checksum 通过 | 删除本地原始文件 |
| `upload_failed` | 单次上传失败 | 记录 `last_error`，计算 `next_retry_at` |
| `upload_expired` | 超过本地保留期 | 删除本地文件，回放显示不可用 |
| `delete_requested` | 用户请求删除 | 阻止新 ASR/评分/补传 |
| `delete_pending_storage` | 对象存储删除中 | 前端不可播放 |
| `deleted_sensitive_data` | 敏感证据已删除 | 保留脱敏摘要和 tombstone |
| `delete_failed` | 删除失败，可重试 | 记录审计和错误 |

### Local Upload Queue

本地队列字段：

| 字段 | 说明 |
|---|---|
| `queue_item_id` | 本地队列 ID |
| `child_id` | 孩子 ID |
| `game_session_id` | 会话 ID |
| `prompt_turn_id` | 提示轮次 ID |
| `local_attempt_id` | attempt 幂等键 |
| `local_recording_id` | recording 幂等键 |
| `file_path` | 应用私有目录路径 |
| `status` | `pending_upload` / `uploading` / `uploaded` / `expired` / `deleted` |
| `retry_count` | 重试次数 |
| `next_retry_at` | 下次重试时间 |
| `expires_at` | 本地保留期限 |
| `last_error` | 最近错误 |
| `checksum_sha256` | 文件校验 |

规则：

- 上传失败不阻塞游戏。
- `expires_at` 从 `recording_completed_at` 开始计算，默认 7 天。
- `uploading` 超时后回到 `pending_upload`。
- 客户端启动时扫描孤儿文件；无元数据绑定或过期则删除。
- 上传成功后删除本地原始文件。
- 家长删除数据时，本地 `local_only` / `pending_upload` / `uploading` 文件必须取消并删除。
- 多 child profile 队列隔离。
- 本地文件只能放应用私有目录，不使用 Downloads 或 external storage。
- 移动端应排除系统云备份。
- 平台允许时本地待上传文件加密；至少依赖系统 sandbox。

## Core Flow

推荐顺序：

1. 后端创建或恢复 `GameSession`。
2. 后端创建 `PromptTurn`，保存内容快照。
3. 录音开始前，客户端生成 `local_attempt_id` 和 `local_recording_id`。
4. 客户端本地创建 pending attempt envelope，绑定 session、prompt、attempt、recording。
5. 玩家录音。
6. 客户端保存本地音频和队列项。
7. 客户端创建/复用 `InteractionAttempt`。
8. 客户端上传录音。
9. 后端创建/复用 `AudioRecording` 元数据，状态 `uploading`。
10. 对象存储 put 到确定性 `storage_key`。
11. 后端校验 checksum。
12. 后端更新 `AudioRecording.status = uploaded`。
13. 后端绑定 `InteractionAttempt`。
14. ASR、实时评分、深评分绑定到同一个 `InteractionAttempt`。
15. 时间线记录 `spell_echo_saved` 和 `magic_response_triggered` 等事件。

## Idempotency

| 对象 | 幂等键 / 唯一约束 |
|---|---|
| `GameSession` | `UNIQUE(child_id, client_session_id)` |
| `PromptTurn` | `UNIQUE(game_session_id, content_id, content_version, sequence_no)` |
| `InteractionAttempt` | `UNIQUE(child_id, local_attempt_id)` |
| `AudioRecording` | `UNIQUE(child_id, local_recording_id)` and `UNIQUE(interaction_attempt_id)` |
| `ASRResult` | `UNIQUE(interaction_attempt_id, audio_recording_id, engine_version)` |
| `AssessmentResult` | `UNIQUE(interaction_attempt_id, stage, rule_version)` |
| `RewardEvent` | `UNIQUE(interaction_attempt_id, reward_policy_id)` |
| `TimelineEvent` | `UNIQUE(game_session_id, idempotency_key)` |

原则：

- 重试不能生成重复 attempt。
- 上传重试不能换 storage key，除非旧对象显式作废。
- `reward_granted` 必须幂等，深评分不得重复发奖励。
- 时间线可重放，但重复事件必须被幂等键吸收。

## Structured Replay

结构化过程回放不是屏幕录像，也不是单独播放录音。

回放基于：

- `GameSession`
- `TimelineEvent`
- `PromptTurn`
- `InteractionAttempt`
- `AudioRecording`
- `ASRResult`
- `AssessmentResult`
- `RewardEvent`

回放回答：

- 孩子当时在哪个言灵场景？
- NPC 或 飞飞 发起了什么提示？
- 孩子第几次尝试？
- 孩子的声音触发了什么言灵回应？
- 飞飞 怎样鼓励？
- 系统如何给出即时反馈？
- 深度分析给出哪些脱敏学习标签？
- 后续个性化练习为什么出现？

## Parent Console UX

家长端定位：成长回顾，不是错题审判。

每个 PromptTurn 显示：

- 场景。
- 任务主题。
- NPC/飞飞 提示。
- 目标词句。
- 尝试次数。
- 正向反馈摘要。
- 可播放录音（仅授权且录音存在时）。
- ASR 文本（仅未删除且家长有权限时）。
- 汇总评分和学习标签。
- 音频质量标签。
- 删除按钮。

不显示：

- “失败次数”。
- 内部错误码。
- 逐词发音错误细节，除非产品另行设计家长解释语。
- 教研/运营入口。

回放状态矩阵：

| 状态 | 家长端展示 |
|---|---|
| `available` | 可播放，显示时长、目标句、评分摘要 |
| `no_speech_detected` | “这次没有检测到有效语音，飞飞 已鼓励孩子再试一次” |
| `too_short` | “录音过短，分析可能不完整” |
| `pending_upload` | “录音同步中” |
| `upload_expired` | “录音未能同步，无法回放” |
| `deleted_sensitive_data` | “录音已删除” |
| `deep_assessment_pending` | “成长分析处理中” |
| `deep_assessment_failed` | “本次深度分析暂不可用，不影响游戏进度” |
| `low_quality_audio` | “环境较吵，分析可能不完整” |

## Child Echo UX

孩子端不做完整历史回放，也不提供录音列表。

可做轻量正向替代：

- 今日言灵回声：展示今日点亮的言灵、星辉、徽章、飞飞 鼓励。
- 可选成功片段回听：只播放最近一次成功点亮言灵的短片段，默认关闭，需家长允许。
- 飞飞 总结：“今天你用英语点亮了 3 次彩虹言灵！”

孩子端不展示：

- 历史录音列表。
- ASR 原文对照。
- 失败/错误统计。
- 详细评分证据。

## Scoring and Personalization

### 实时轻评分

输入：

- ASR 文本。
- 当前目标句。
- `PromptTurn` 内容快照。

用途：

- 即时反馈。
- 言灵回应。
- 当场奖励。

规则：

- 超时目标：2 秒。
- 超时或失败时游戏继续。
- UI 使用 飞飞 支持语，不说“失败”。
- 状态标记 `degraded`，避免错误发放高阶奖励。

### 异步深评分

输入：

- canonical 录音。
- ASR 结果。
- `PromptTurn` 内容快照。
- `InteractionAttempt` 上下文。
- 音频质量标签。

用途：

- 家长报告。
- 长期学习画像。
- 个性化内容生成。

规则：

- 可排队、可重试、可延迟。
- 深评分不得撤销已发即时奖励。
- 录音未上传：`waiting_recording`。
- 录音删除：`recording_unavailable`。
- 连续失败 3 次：`assessment_failed`。
- 个性化系统不得使用已删除录音、ASR 原文、可重建孩子原话的信息。

## Privacy and Consent

儿童语音、ASR 原文、逐词置信度、详细发音错误片段是高敏感数据。

### 家长同意

录音保存和长期使用需要家长同意。建议拆分同意项：

1. 完成学习任务必要处理。
2. 家长成长回顾中播放录音。
3. 长期学习画像。
4. 个性化内容生成。
5. 内部研究抽样。

撤回同意后：

- 停止新录音保存或对应用途。
- 删除或停止使用既有原始录音和 ASR 原文。
- 保留最小化学习记录：场景、任务、是否完成、尝试次数、汇总分段、脱敏标签。

### 保留期

用户偏好：后端长期保存，不自动删除，用户需要时自行清除。

隐私基线：

- 必须提供家长清除入口。
- 必须提供关闭长期保存的设置。
- 必须支持后续配置默认保留期。
- 若面向真实儿童上线，保留期和同意策略需经产品/法务确认后才能实现。

本规划建议 Implementation MVP 至少支持：

- 家长手动删除单条录音。
- 家长删除某次游戏会话的录音和敏感文本。
- 家长删除全部孩子数据。
- 撤回个性化使用同意。

### 删除矩阵

| 删除类型 | 对象存储 | ASR 原文 | 详细评分证据 | 脱敏汇总 | 时间线 | 本地队列 | 审计 |
|---|---|---|---|---|---|---|---|
| 删除单条录音 | 删除 | 删除 | 删除 | 保留 | 保留 | 删除对应项 | 保留最小审计 |
| 删除会话录音 | 删除会话下全部 | 删除 | 删除 | 保留 | 保留 | 删除对应项 | 保留最小审计 |
| 删除全部孩子数据 | 删除全部 | 删除全部 | 删除全部 | 按账户删除策略处理 | 按账户删除策略处理 | 删除全部 | 保留合规审计 |
| 撤回个性化 | 可按家长选择删除 | 删除或停用 | 删除或停用 | 可保留 | 保留 | 不再补传非必要录音 | 保留同意变更审计 |

删除屏障：

- 设置 `deletion_requested_at` 后，补传、ASR、深评分、个性化任务启动前必须检查 tombstone。
- 本地补传队列看到 tombstone 必须删除本地文件，不得上传。
- 对象存储删除失败进入 `delete_failed`，前端仍不可播放。
- 删除接口幂等，重复删除返回当前 tombstone 状态。

### 访问审计

MVP 若支持播放，必须审计：

- 播放 URL 签发。
- 原始录音访问。
- ASR 原文查看。
- 删除。
- 导出。
- 管理员访问尝试。

审计字段：

- `audit_event_id`
- `actor_type`
- `actor_id`
- `action`
- `target_type`
- `target_id`
- `child_id`
- `purpose`
- `consent_id` or `approval_ticket_id`
- `ip`
- `user_agent`
- `created_at`
- `result`

审计日志不得包含：

- 原始 URL。
- ASR 原文。
- 孩子回答片段。
- 可播放音频内容。

## Access Control

规则：

- 家长只能访问自己孩子的会话、回放、录音。
- 孩子端 token 只能创建当前 session、attempt、上传当前 attempt recording。
- 孩子端不能列出历史录音，不能获取播放 URL。
- 服务端必须验证 `parent_id -> child_id` 归属。
- 服务端必须验证 `interaction_attempt_id` 属于当前 child 和 session。
- 对象 key 由服务端生成，客户端不能自定义路径。
- 上传接口限制大小、时长、格式、采样率，并校验真实音频容器。
- 教研/运营默认只能访问脱敏摘要。
- 管理员访问原始录音需要审批、审计、限定时长、限定样本。

播放规则：

- bucket 私有。
- 不返回长期 `raw_url`。
- 家长播放必须通过后端鉴权接口生成短期 URL，例如 5 分钟。
- 如果短期 URL 不进 Implementation MVP，则不提供音频播放，只显示结构化记录和评分摘要。

## Dependencies

| 系统 | 依赖内容 |
|---|---|
| Godot Client | 录音、本地队列、VAD、混音 ducking、时间线本地事件 |
| voice-service | ASR、服务端 VAD、音频校验、canonical 转码 |
| assessment-service | 实时轻评分、异步深评分 |
| quest-service | `quest_id`、任务状态、PromptTurn 关联 |
| reward-service | 幂等奖励发放 |
| dialogue-service | NPC/飞飞 提示、反馈事件 |
| auth-service | 家长/孩子鉴权、授权关系 |
| parent-dashboard | 成长回顾、播放、删除入口 |
| object storage | 私有 bucket、上传、删除、短期 URL |
| audit/logging | 访问、播放、删除、同意变更审计 |

## Tuning Knobs

| 参数 | 默认值 | 范围 | 说明 |
|---|---:|---:|---|
| `word_recording_max_s` | 8 | 5-10 | 单词跟读上限 |
| `sentence_recording_max_s` | 12 | 8-15 | 短句跟读上限 |
| `short_answer_max_s` | 20 | 12-25 | 简短回答上限 |
| `free_response_max_s` | 30 | 20-30 | 自由表达上限 |
| `vad_no_speech_timeout_s` | 6 | 5-8 | 无语音等待 |
| `vad_min_speech_ms` | 300 | 300-500 | 最小有效语音 |
| `pre_roll_ms` | 400 | 300-500 | 起音保护 |
| `post_roll_ms` | 700 | 500-800 | 尾音保护 |
| `local_retention_days` | 7 | 1-7 | 本地待补传保留 |
| `upload_retry_max` | 10 | 3-20 | 最大补传次数 |
| `playback_url_ttl_min` | 5 | 1-10 | 短期播放 URL 过期 |
| `realtime_assessment_timeout_s` | 2 | 1-3 | 实时评分超时 |
| `deep_assessment_retry_max` | 3 | 1-5 | 深评分重试 |
| `bgm_duck_db` | -18 | -24 到 -12 | 录音期间 BGM duck |

## Failure Modes

| 场景 | 处理 |
|---|---|
| 网络离线 | 本地保存、队列 `pending_upload`、游戏继续 |
| App 崩溃 | 启动时扫描 pending envelope 和孤儿文件 |
| 队列有记录但文件丢失 | 标记 `upload_expired` 或 `local_file_missing`，回放不可播放 |
| 文件存在但队列缺失 | 若可匹配 envelope 则恢复；否则删除孤儿文件 |
| 上传成功但本地删除失败 | 标记清理失败，后台重试删除 |
| 重复上传 | 幂等键吸收，不生成重复对象 |
| 对象存储失败 | `upload_failed`，退避重试 |
| 磁盘不足 | 不开始录音或尽快清理过期 pending 文件，飞飞 温柔提示 |
| ASR 不清晰 | `asr_unclear`，飞飞 提示再试或示范 |
| 实时评分超时 | `degraded`，游戏继续，不撤销尝试 |
| 深评分失败 | `assessment_failed`，家长端显示分析暂不可用 |
| 删除中有任务排队 | tombstone 阻止补传/ASR/评分/个性化继续 |
| 未授权访问录音 | 返回 403，不泄露资源是否存在 |

## Acceptance Criteria

### Planning MVP

- Given 当前阶段为 Planning MVP
  - When 设计审查运行
  - Then 文档包含领域模型、状态机、权限、隐私、音频规则、失败场景、验收标准。

### 会话边界

- Given 玩家从主菜单进入 `MistyBay`
  - When 场景加载完成
  - Then 创建 1 条 `GameSession`
  - And 状态为 `active`
  - And 时间线记录 `session_started` 与 `scene_entered`。

- Given 玩家从 `MistyBay` 切换到 `LanternCourtyard`
  - When 新场景加载完成
  - Then 旧 `GameSession` 状态为 `ended`
  - And 新建 1 条 `GameSession`
  - And 同一 child 不存在两个 active 学习会话。

- Given App 崩溃时存在 active session
  - When 下次启动
  - Then 上一次 session 标记为 `abandoned` 或由服务端超时标记 `expired`。

### 录音与 Attempt 绑定

- Given 一个 `PromptTurn` 已创建
  - When 玩家完成一次有效录音
  - Then 创建或复用 1 条 `InteractionAttempt`
  - And 创建 1 条 `AudioRecording`
  - And 二者可通过 ID 双向追溯。

- Given 客户端使用同一个 `local_attempt_id` 重试 3 次
  - When 后端收到请求
  - Then 只存在 1 条 `InteractionAttempt`。

- Given 玩家持续说话 35 秒
  - When 录音达到 30 秒
  - Then 客户端自动停止录音
  - And 保存音频时长在 29.5-30.5 秒之间
  - And 只生成 1 条 `AudioRecording`
  - And `quality_flags` 或状态包含 `max_duration_reached`。

- Given 玩家点击录音但 6 秒内无有效语音
  - When VAD 判定无语音
  - Then 不上传音频文件
  - And `InteractionAttempt.recording_status = no_speech_detected`
  - And 时间线记录 `no_speech_detected`。

### 本地保存与补传

- Given 网络离线
  - When 录音完成
  - Then 本地文件保存成功
  - And 队列中存在 `pending_upload` 记录
  - And 游戏流程不阻塞。

- Given App 在录音保存后、上传前崩溃
  - When 下次启动
  - Then 客户端恢复补传任务
  - And 不生成重复 `InteractionAttempt`。

- Given 本地待补传录音创建时间超过 7 天
  - When App 启动或补传任务运行
  - Then 状态变为 `upload_expired`
  - And 本地原始音频被删除
  - And 时间线仍可展示但录音不可播放。

- Given 上传成功
  - When 本地清理执行
  - Then 本地原始录音文件被删除。

### 对象存储和播放

- Given 录音上传成功
  - When 检查对象存储
  - Then bucket 为私有
  - And DB 保存 `storage_key` 而非长期可播放 URL。

- Given 未登录用户获得某条对象路径
  - When 直接访问
  - Then 请求失败。

- Given 家长 A 登录
  - When 请求家长 B 孩子的录音
  - Then 后端返回 403。

- Given 家长请求自己孩子的录音播放
  - When 鉴权通过
  - Then 后端返回短期播放 URL 或代理播放响应
  - And 记录访问审计。

### 删除与隐私

- Given 家长删除单条录音
  - When 删除完成
  - Then 对象存储文件不可访问
  - And `AudioRecording.deleted_at` 非空
  - And ASR 原文、逐词置信度、发音错误片段为空或被脱敏
  - And 回放页面显示“录音已删除”
  - And 审计日志记录操作者、时间、录音 ID。

- Given 对象存储删除失败
  - When 删除请求执行
  - Then 前端不可播放
  - And 状态为 `delete_failed`
  - And 后台重试删除。

- Given 删除 tombstone 已存在
  - When 补传、ASR、深评分、个性化任务启动
  - Then 任务停止处理该录音。

### 回放

- Given 一次 session 有 2 个 PromptTurn，每个有多次尝试
  - When 家长查看结构化回放
  - Then 能看到场景、NPC/飞飞 提示、尝试次数、言灵回应、飞飞 鼓励、评分摘要、奖励事件。

- Given 某条录音为 `upload_expired`
  - When 查看回放
  - Then 展示该尝试存在
  - And 展示“录音未能同步，无法回放”
  - And 页面不报错。

- Given 某条录音已删除
  - When 查看回放
  - Then 时间线仍显示学习过程
  - And 不显示 ASR 原文
  - And 显示“录音已删除”。

### 评分

- Given 实时评分服务超过 2 秒无响应
  - When 玩家提交录音
  - Then 游戏流程继续
  - And 显示 飞飞 支持性反馈
  - And `realtime_assessment_status = degraded`
  - And 不错误发放高阶奖励。

- Given 深评分任务连续失败 3 次
  - When 后台任务结束
  - Then `deep_assessment_status = failed`
  - And 家长报告显示“深度分析暂不可用”。

### 音频质量

- Given 录音发生明显 clipping
  - When 后端音频校验完成
  - Then `quality_flags` 包含 `clipped`
  - And 家长端显示质量提示。

- Given 录音期间系统 TTS 串入麦克风
  - When 后端检测到可能串音
  - Then `quality_flags` 包含 `possible_playback_leakage`
  - And 深评分不得把该结果作为强证据。

## Open Questions

- canonical 音频采样率最终选 16 kHz 还是 24 kHz。
- 播放代理格式优先 `m4a/aac` 还是 `webm/opus`。
- 真实上线前默认保留期是否仍允许“不自动删除”。
- 家长是否可以导出录音；若允许，导出链接和审计规则需另行设计。
- 内部研究抽样是否进入任何 MVP；若进入，需要单独审批流。
- Supabase Storage 是否满足私有 bucket、短期 URL、删除审计需求。

## Future Evolution

- 家长控制台完整成长回顾页面。
- 短期 URL 播放和访问审计。
- 后端流式播放。
- 深评分任务队列。
- 个性化内容生成管线。
- 保留期配置。
- 教研授权听音流程。
- 数据导出流程。
- 多段长回答录音支持。
