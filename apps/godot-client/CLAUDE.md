# Godot 客户端开发注意事项

本文件记录本项目在 Godot 场景开发中容易踩坑的约束与检查点。开发 `apps/godot-client/` 下的场景、语音交互、任务流程时优先遵守。

## 1. 场景不是英语练习页，必须先是 RPG 行为

- 任务文案不要写成“说出某句型 / Say the sentence”。
- 每次英语表达都要包装成游戏动作：问候、介绍、请求、指路、唤醒物件、修复机关、帮助 NPC、完成仪式等。
- 示例：
  - 不推荐：`任务：说出 Her name is A-Ling`
  - 推荐：`任务：向掌柜介绍阿灵`
- 如果新增课堂目标句型，先问：“玩家在世界里为什么要说这句话？”再写 quest 文案和反馈。
- NPC 语言约束：除了 `feifei` 教练可以说中文（用于提示、解释、引导），其它所有 NPC 只能说目标语言（英语），不得在对话台词中出现中文。

## 2. 录音流程统一由 `VoicePipeline` 控制

- 场景 controller 不要自己实现硬上限停止逻辑。
- `VoicePipeline` 负责：
  - 开始/停止麦克风
  - `is_listening` / `is_recording` 状态
  - `voice_started` / `voice_ended` / `listening_stopped` 信号
  - 录音硬上限 `max_duration_reached`
  - no-speech 记录
  - BGM/SFX/TTS duck 开始与结束
- 场景只负责：
  - 进入等待语音状态
  - 调用 `VoicePipeline.start_listening(recording_context)`
  - 在 `voice_ended(audio_data)` 后调用 ASR
  - 根据 ASR 结果推进任务状态

## 3. 语音任务必须提供 recording context，或确保可自动补齐

录音开始前需要能创建：

- `local_attempt_id`
- `local_recording_id`
- pending recording envelope
- `InteractionAttempt`
- timeline event

`VoicePipeline.start_listening(recording_context)` 的 context 建议包含：

```gdscript
{
	"scene_id": "chang_an_market_lesson_01",
	"quest_id": "review_a_ling",
	"content_id": "review_a_ling_prompt",
	"prompt_text_snapshot": "向掌柜介绍阿灵",
	"target_utterance_snapshot": "Her name is A-Ling.",
	"attempt_type": "short_answer",
	"expected_answer_type": "short_answer",
}
```

如果没有传 `game_session_id` / `prompt_turn_id`，`VoicePipeline` 会尝试通过 `MagicEchoManager` 的 active session 自动补齐；但新增学习场景时仍要确认：

- `MagicEchoManager.SCENE_ID_MAP` 包含该场景映射
- `MagicEchoManager.LEARNING_SCENES` 包含规范化后的 scene id
- `GameManager.current_scene` 能正确反映当前场景

## 4. no-speech 不是“什么都不做”

无有效语音时：

- 不应上传音频文件
- 仍应保留 `InteractionAttempt`
- 应记录 `no_speech_detected` timeline event
- 场景可以显示重试/教练提示，但不要绕过底层记录链路

如果 no-speech 没有记录，优先检查是否在录音开始前创建了 pending envelope。

## 5. 录音硬上限必须从监听窗口开始计算

- 硬上限应从 `start_listening()` 后开始，而不是从第一次检测到语音后开始。
- 到达硬上限后必须：
  - 标记 `max_duration_reached`
  - 停止 listening/recording
  - 停麦克风
  - 清 AudioEffectCapture buffer
  - 结束 duck
  - 避免继续监听或重复触发录音

不要在多个场景里复制 `if record_duration > MAX_RECORD_DURATION: stop_listening()` 逻辑；这会导致 completion reason 丢失或状态不一致。

## 6. BGM/SFX/TTS duck 必须成对

录音期间要避免系统音进入录音窗口：

- 开始 listening 时调用 duck begin
- 任何结束路径都必须 duck end：
  - 正常 speech_detected
  - no_speech_detected
  - max_duration_reached
  - 手动 stop_listening
  - API/场景中断

新增提前 return 或错误分支时，检查是否会漏掉 duck end。

## 7. ASR postprocess 结果通过 `HybridAPI` helper 读取

场景不要散读 `result.postprocess.*`。统一使用：

- `HybridAPI.get_asr_corrected_text(result)`
- `HybridAPI.get_asr_extracted_value(result, key, fallback)`
- `HybridAPI.get_asr_intent(result)`
- `HybridAPI.get_asr_intent_matched(result, fallback)`
- `HybridAPI.get_asr_guidance_npc_line(result, fallback)`

这样 voice-service 输出结构变化时只改 `HybridAPI`。

## 8. 委托意图由客户端完成，不由 voice-service 造值

voice-service 只识别：

- `provide`
- `delegate`
- `off_topic`

客户端负责：

- 值池
- pick 策略
- 推荐语
- 槽位状态机
- 多轮确认

对于可委托槽位，推荐状态为：

```text
AWAITING -> PROPOSED(value) -> FILLED(value)
```

规则：

- `delegate`：从本地值池选值并提议
- `PROPOSED` 下再次 `delegate`：换一个，排除近期提议值
- `PROPOSED` 下只有 `extracted[key]` 非空时才落定
- 不要把“好 / 可以 / yes”直接当成槽位值；应让 ASR postprocess 根据 `proposed_value` 回填
- 不要把开放姓名值池塞进 `candidate_answers`，否则会误变成封闭题

## 9. `candidate_answers` 只用于封闭题

适合：

- 唤醒词：`书架 / bookshelf / book shelf`
- 选择题
- 固定命令
- 固定物品名

不适合：

- 玩家姓名
- 自由回答
- 开放对话

开放槽位如果需要可委托，使用 slot 扩展字段：

```gdscript
{
	"key": "name",
	"type": "person_name",
	"delegatable": true,
	"value_pool": ["Carl", "Wendy"],
	"pick_strategy": "exclude_recent",
	"slot_state": "proposed",
	"proposed_value": "Carl",
}
```

## 10. 崩溃恢复依赖默认自动读档

不要默认关闭：

```ini
[game]
test_mode_skip_auto_load_save=false
```

如果测试需要跳过读档，应通过测试命令行或测试专用设置覆盖，不要提交为默认值。

启动恢复路径应能：

- `GameManager.load_progress()`
- `MagicEchoManager.import_state()`
- `MagicEchoManager.reconcile_local_recordings()`
- 保留 pending upload 或清理无法绑定的孤儿文件

## 11. 切场景不要在 `_ready()` 中直接抢切

Godot 可能报：

```text
Parent node is busy adding/removing children, remove_child() can't be called at this time.
```

如果 `_ready()` 中需要 resume 到其他场景，优先延迟：

```gdscript
call_deferred("_resume_to_saved_scene")
```

或等待一帧后切换。避免在节点树还在添加/删除时直接 `change_scene_to_file()`。

## 12. UI 显示状态要来自系统真实状态

例如 pending upload 徽标：

- UI 不维护自己的计数
- 从 `MagicEchoManager.get_pending_uploads()` 派生
- 只显示可观察状态，不改变队列状态

场景 UI 应尽量只读 autoload 状态，业务状态变化由 manager/pipeline 负责。

## 13. 测试与验证

每次改 Godot 场景/语音链路后至少做：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --check-only
```

若涉及 GUT 测试，优先跑目标测试；如果 GUT runner 卡住，只能说明未得到测试结果，不能报告为通过。

语音链路手动验收建议覆盖：

- 正常有效语音 -> 本地文件存在 -> pending upload 出现 -> 游戏不阻塞
- no-speech -> 不上传音频 -> InteractionAttempt/timeline 保留
- 录音超过硬上限 -> `max_duration_reached` -> 停麦克风/结束 duck
- 崩溃/重启 -> pending envelope 恢复或孤儿文件清理
- ASR test mode -> 不打开麦克风，使用测试音频/默认答案推进流程

## 14. 改动边界

- 不要把一个 issue 的实现混入无关场景、无关服务、无关文档清理。
- 如果必须触碰多个子系统，说明原因，并确保每个改动都能追溯到验收标准。
- 发现相邻问题可以记录，但不要顺手大范围重构。

## 15. 常用相关文件

- `project.godot` — autoload、输入、测试模式配置
- `assets/scripts/autoload/VoicePipeline.gd` — 录音/VAD/duck/envelope 主控
- `assets/scripts/autoload/MagicEchoManager.gd` — GameSession/PromptTurn/InteractionAttempt/timeline/pending upload
- `assets/scripts/autoload/HybridAPI.gd` — ASR/TTS/API helper
- `assets/scripts/autoload/GameManager.gd` — 存档、恢复、当前场景
- `assets/scenes/ui/VoiceMicIndicator.tscn` — 麦克风与 pending upload 可见状态
- `test/autoload/test_magic_echo_manager.gd` — 本地录音队列核心测试
- `test/autoload/test_hybrid_api_asr_context.gd` — ASR context/postprocess helper 测试
