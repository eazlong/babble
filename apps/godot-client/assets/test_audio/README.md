# ASR 测试模式音频目录

打开 `hybrid_api/asr_default_answer_test_enabled` 后，VoicePipeline 会跳过麦克风，
把录好的 wav 当麦克风输入，走**真实** whisper + voice-service postprocess。

## 答案由「场景自己声明」（重要）

**不要**把答案顺序集中写在 `project.godot` 的 `asr_test_audio_names` 里。全局顺序无法同时
满足"从序章开始玩"和"带存档续到某个场景"——出过一次事故：玩家带存档续进蜃影客栈时，
全局轮换仍停在开头，于是「唤醒画卷」这一轮放的是序章的名字答案，孩子怎么说都过不去
（现象就是"说要说出画卷口令时一直不成功"）。

现在的归属：

| 场景 | 答案由谁声明 | 文件 |
|---|---|---|
| 序章 BeginningFP | `BeginningFPController.TEST_ASR_NEW_GAME_ANSWERS`（全新开局）/ `TEST_ASR_RESUME_ANSWERS`（续行） | `pa_01`,`pa_02` / `pa_04` |
| 蜃影客栈导览 | `MirageInnIntroductionController.TEST_ASR_INTRO_ANSWERS` | `pa_03` |
| 蜃影客栈 hub | `MirageInnIntroductionController.TEST_ASR_HUB_ANSWERS` | `pa_04` |
| 长安西市 Lesson01/02 | `scene_configs/chang_an_market_lesson_0*.json` 的 `test_asr_audio_names` | `pa_05…pa_11` / `pa_12…pa_18` |

每个场景在 `_ready()` 里 `set_asr_default_answer_test_enabled(...)` + `reset_asr_test_audio_index()`，
所以从哪儿进来都对得上。`project.godot` 里只留一条占位（启动到第一个场景之前用；别留空，
空列表会让收集逻辑退化成"把本目录所有 wav 都排进来"）。

## 玩家台词（`pa_*`，流程测试用）

由 `scripts/record_player_answers.py` 生成，配套清单 `player_answers.json`（含每轮的 ASR 实测
文本与课堂判定档位）。改台词后重跑脚本即可，它会顺带用真实 ASR + 课堂判定复核每一轮；
`--sync-project-settings` 会把轮换表写回 `project.godot`（默认只打印，防手抄漂移）。

几条录制的教训：

- **不要只录孤立关键词**。实测 whisper 把单独的口令稳定误听（早期的「书架」就被听成「输家」，声调错），
  只能靠 postprocess 纠；而失败过一轮后 `recent_turns` 里多了错答案，模型就不再纠了。
  口诀是**给口令补足上下文**：现在的「画中小世界，请回答。」转出的是完整句子，
  postprocess 再纠成「画中小世界 请回答」，首轮/重问都稳。
- **繁体要归一**。whisper 对普通话口令常输出繁体（`出发`→`出發`、`画中小世界`→`畫中小世界`），
  客户端的口令匹配已加 `StoryContinueMarkers.normalize_variants()`（`畫`→`画` 就为此存在）。
- **答案要能被课堂判定接受**。课堂用 `LessonResponseMatcher`；报名字那一步 ASR 有时只回裸名
  （`"Leo"`），控制器会把玩家名字并进 candidate_answers 兜住。

## 其它文件

- `wo_jiao_kaka_kaka_de_ka.wav`、`bang_wo_qi_yi_ge_ba.wav`、`ok.wav`、`shu_jia.wav`：
  早期手录的零散样本（含「帮我起一个吧」的委托用例），仍被单测/手动排查引用。
- `tts/`：**NPC 台词**录音（录制回放模式用），由 `scripts/record_dialogue_tts.py` 生成，
  与 ASR 输入无关；该目录带 `.gdignore`，不走 Godot 导入。

## 人工补录的命名

按轮换顺序编号，例如 `01_hello.wav`、`02_carl.wav`。
`pa_*` 这组由脚本统一生成，别手改名——顺序和键都写在脚本里。
