# Word Spirit Library Scene — 归卷厅场景设计（纯语音交互）

**系统名称**: Word Spirit Library — Archive Hall Scene (词灵阁·归卷厅场景)
**版本**: 0.2
**日期**: 2026-07-22
**状态**: Draft
**所属游戏**: LinguaQuest RPG
**父文档**: `design/gdd/word-spirit-library.md` §3.3 归卷厅
**依赖系统**: VoicePipeline, MagicEchoManager, GameManager, HybridAPI, LXP Assessment, Star Economy, Spirit Coach, Dialogue System

---

## 0. 文档定位与核心约束

本文档只设计**归卷厅场景本身**，不扩张到机关阁、残卷室、回声廊、时光回廊。玩法规则权威以 `word-spirit-library.md` §3.3 为准。

**本版本（0.2）的核心约束：纯语音交互。** 玩家与场景的全部交互——进入入口、召唤字母精灵、拼写单词、确认、朗读、请求帮助、退出——**必须通过语音完成**，不使用鼠标点击、触摸点击或键盘输入。视觉元素仅用于呈现状态与反馈，不作为输入手段。

这一约束使字母 ASR 识别成为本场景的核心技术难点。本文档诚实说明识别风险与兜底策略，不假装识别完美。

---

## 1. 场景概念与幻想

### 1.1 空间叙事定位

归卷厅是词灵书阁深处的一间**刻印工坊**。玩家被书柜守灵引入这间半露天的石质庭院：四周是高耸的书架岩壁，26 个字母精灵以发光符文形态栖息在岩壁的凹槽里；庭院中央是一座待刻印石碑。

这是一间**召唤与刻印的仪式场所**：玩家用声音召唤字母精灵、用声音朗读词灵之名、用声音确认刻印。**整个仪式完全用声音进行**——玩家的声音是唯一能唤醒并驱动这个空间的魔法。这也呼应了语言学习 RPG 的核心：声音就是魔法。

### 1.2 目标 MDA Aesthetics

- **Fantasy**（主导）：用声音召唤字母精灵、朗读其名、刻印成铭文——玩家的声音是刻印仪式的唯一媒介。
- **Challenge**：每日 8-12 张词牌，每张都是一次声音召唤与朗读挑战。
- **Discovery**：生僻字母精灵藏在岩壁深处，玩家需用声音呼唤其名才能召唤。
- **Submission**：短时、低压力、可重复的日常声音仪式。

### 1.3 书柜作为入口的呈现

书阁大厅一侧有巨型书柜墙。其中一卷"归卷轴"微微发光、轻轻浮动。玩家**对书柜说话**即可唤醒书柜守灵，被守灵引入归卷厅——不是点击抽取，而是**声音唤醒**。

---

## 2. 空间布局

### 2.1 总体分区

归卷厅采用**单一中心舞台 + 环形字母岩壁**的布局，固定摄像机视角面向石碑。所有字母精灵以发光符文形态可见，但**不可被点击**——它们只响应玩家的声音。视觉的作用是：让玩家看见字母精灵的位置（建立空间记忆）、看见当前拼写进度、看见阶段反馈。

```
                    ┌─────────────────────────────────┐
                    │      字母岩壁（上层·生僻字母）      │
                    │   V  W  X  Y  Z  Q  K  J  ...     │
                    │                                   │
   字母岩壁         │      字母岩壁（中层·次常用）        │         字母岩壁
  （左侧·常用）      │    F  G  H  L  M  N  P  R  ...    │      （右侧·常用）
   A  E  I  O       │                                   │       B  C  D  T
   S  T  U          │          ┌─────────────┐          │
                    │          │  待刻印石碑  │          │
                    │          │  （中央舞台） │          │
                    │          └─────────────┘          │
                    │     [词牌架]      [feifei 引导位]   │
                    │                                   │
                    │         [Spark 随身位]              │
                    │      字母岩壁（下层·最常用）         │
                    │      A  E  I  O  N  R  S  T       │
                    └─────────────────────────────────┘
```

### 2.2 各功能区位

| 区位 | 位置 | 功能 | 交互方式 |
|------|------|------|---------|
| **书柜入口** | 词灵书阁大厅北侧墙面 | 进入归卷厅的触发点 | 玩家对书柜说话唤醒守灵 |
| **中央石碑舞台** | 场景正中央 | 刻印目标单词的载体 | 被动呈现刻印结果 |
| **词牌架** | 石碑左前方 | 展示当前词牌 + 剩余词牌 | 被动呈现线索 |
| **字母岩壁** | 环绕场景三面 | 26 字母精灵栖息地 | 玩家说出字母名唤醒对应精灵 |
| **拼写槽位条** | 石碑正前方浮空 | 显示玩家已召唤的字母序列 | 被动呈现拼写进度 |
| **Spark 随身位** | 屏幕右下角浮空 | Spark 陪伴与示范 | 被动呈现反馈 |
| **feifei 引导位** | 词牌架旁 | feifei 教练中英引导位 | 被动呈现引导 |
| **墨影词牌区** | 场景左下角暗格 | 展示重试队列词牌 | 被动呈现 |

### 2.3 玩家动线（注意力动线）

玩家视角固定，动线是**注意力动线**，由阶段焦点高亮（§4.5）和语音提示引导：

```
书柜入口（语音唤醒守灵）
  → 词牌架（查看当前词牌线索）
  → 字母岩壁（说出字母名召唤精灵）
  → 拼写槽位条（语音确认拼写）
  → 石碑中央（朗读单词刻印）
  → 词牌架（下一张词牌）
  → 循环至词牌清空
  → 语音退出（返回书阁大厅）
```

---

## 3. 入口交互：语音唤醒书柜守灵

### 3.1 设计原则

入口是**声音唤醒仪式**：玩家对书柜说话，唤醒书柜守灵，被守灵引入归卷厅。没有任何点击或触摸。

### 3.2 入口流程

```
[Phase 1] 玩家在书阁大厅面向书柜墙
  - 书柜墙是视觉热点区域，归卷轴轻微浮动 + 发光呼吸
  - 守灵处于休眠态，半透明的符文形态嵌在书页间
  - 屏幕出现 soft prompt（仅视觉提示，无文字指令）：
    守灵头顶一个柔和的声波涟漪图标，提示"对书柜说话"

[Phase 2] VoicePipeline 处于入口监听模式
  - start_listening(recording_context={attempt_type: "wake_guardian"})
  - 玩家说出任意英语问候/唤醒语，例如：
    "Hello" / "Hi" / "Guardian" / "Open" / "Archive" / "Word spirits"
  - ASR 识别后，HybridAPI.get_asr_intent(result) 返回任意非空 intent
    即视为唤醒成功（入口阶段不严格匹配内容，只确认玩家开口）
  - no-speech：守灵保持休眠，10s 后 Spark 飞出提示："Try saying hello to the guardian."

[Phase 3] 唤醒成功
  - 守灵从书页间现身，符文化为实体
  - 守灵用英语说一句引导语（方向见 §8.4）
  - 卷轴光幕展开覆盖屏幕 → 场景切换至归卷厅

[Phase 4] 进入归卷厅
  - 淡入动画：玩家视角从卷轴光幕中"落下"到归卷厅中央
  - feifei 仅在首次进入时用中文做一句新手引导（见 §8.3）
  - 词牌架自动浮起第一张词牌
  - VoicePipeline 停止入口监听，进入拼写阶段监听模式（见 §6）
```

### 3.3 退出流程

```
[Phase 1] 玩家在任何阶段说退出指令（"leave" / "exit" / "stop" / "quit"）
  - ASR 识别到 exit intent
  - 若有未完成词牌：守灵提示 "Some word spirits are still waiting. Leave anyway?"
    - 玩家说 "yes" / "leave" → 保存进度，退出
    - 玩家说 "no" / "stay" / "continue" → 关闭提示，继续
  - 若全部完成：守灵播放完成语，展示刻印报告，发放星星

[Phase 2] 卷轴光幕收起 → 返回书阁大厅书柜前
```

退出不强制完成所有词牌，未完成词牌保留为"待刻印"状态，次日刷新时按遗忘曲线重新编排。

---

## 4. 核心玩法循环的场景化落地

### 4.1 场景化循环（纯语音）

```
1. 取词牌      — 词牌架自动浮起词牌（无玩家操作）
2. 召唤字母    — 玩家说出字母名（letter name），对应精灵飞入槽位
3. 拼写确认    — 玩家说 "done" / "ready" 确认拼写
4. 朗读刻印    — 拼写正确后，玩家朗读目标单词
5. ASR 判定    — VoicePipeline 录音 → ASR → HybridAPI 读取结果
6. 刻印结果    — 通过：铭文刻入石碑，星星飞出
                 未通过：字母散落，词牌变墨影词牌
7. 下一张      — 玩家说 "next" 或自动浮起下一张词牌
```

### 4.2 每一步的 RPG 动作包装

| 步骤 | 英语练习本质 | RPG 动作包装 | 场景表现 |
|------|-------------|-------------|---------|
| 取词牌 | 看到题目 | 取下悬浮的待刻卷轴 | 词牌从词牌架飞到石碑前方展开 |
| 召唤字母 | 说字母名 | 用声音呼唤栖息在岩壁的字母精灵 | 玩家说 "A"，A 符文亮起，精灵化形飞入槽位 |
| 拼写确认 | 确认拼写 | 用声音宣告刻印开始 | 玩家说 "done"，槽位条整体发光，石碑准备刻印 |
| 朗读 | 读单词 | 对着石碑呼唤词灵之名 | 石碑中央出现朗读光环 |
| 判定 | ASR 评分 | 词灵回应共鸣度 | 共鸣度高→铭文刻入；低→精灵散落 |
| 刻印成功 | 答对 | 词灵永久铭刻进书阁 | 铭文发光留驻，星星飞向星星条 |
| 刻印失败 | 答错 | 词灵暂未稳定，化为墨影 | 字母精灵散落回岩壁，词牌变墨影 |

### 4.3 阶段状态机

```
IDLE（空转，等待取词牌）
  → SPELLING（拼写阶段：VoicePipeline 监听字母名/指令）
    → SPELL_CONFIRM（玩家说 "done"，判定拼写是否正确）
      → 正确 → READING（朗读阶段：监听单词发音）
      → 错误 → 回到 SPELLING（不消耗朗读机会）
    → READING
      → ASR 判定中 → JUDGING
        → 通过 → INSCRIBING（刻印动画 + 星星发放）
        → 未通过 → SCATTERING（散落动画）→ 墨影化 → IDLE
        → ASR 不可用 → PLAYBACK_REVIEW（录音回放自评）
  → INSCRIBING → IDLE 取下一张
  → 词牌清空 → COMPLETE
```

### 4.4 单词词牌线索呈现

| 线索类型 | 词牌正面呈现 |
|---------|-------------|
| 中文释义 + 拼写 | 中文释义文字 + 主题插图 |
| 图片线索 + 拼写 | 只显示图片 |
| 例句缺词 + 拼写 | 例句，缺词位置为发光空槽 |
| 听音拼写（进阶） | 只显示"聆听"图标，单词发音由 feifei 语音播报或 TTS 自动播放，无需玩家点击 |
| 近义/反义辨析 | 线索词（如 "opposite of: hot"） |

词牌不直接显示英文目标词。听音拼写题型中，单词发音由 feifei 语音播报或 TTS 自动播放，无任何点击交互。

### 4.5 阶段焦点高亮

为避免玩家不知道该说什么，当前阶段对应的视觉焦点会高亮，并配合 Spark/feifei 的语音提示：

- **SPELLING**：字母岩壁整体微微泛光；Spark 飞出提示 "Say a letter to call a spirit."
- **READING**：字母岩壁变暗，石碑中央朗读光环高亮 + 麦克风指示器亮起；Spark 提示 "Now say the word."
- **JUDGING**：石碑光环旋转，其他区域变暗。
- **INSCRIBING**：石碑铭文逐字点亮，星星飞出轨迹高亮。
- **SCATTERING**：字母精灵散落轨迹高亮，墨影词牌区短暂亮起。

---

## 5. 字母精灵召唤与拼写（纯语音）

### 5.1 字母精灵的空间分布

字母精灵按使用频率分层分布在环形岩壁上，让常用字母易被看见、生僻字母需要玩家抬头寻找。在纯语音模式下，"寻找"是**视觉定位 + 语音呼唤**——玩家看见生僻字母在上层，说出其名即可召唤。

| 层级 | 位置 | 字母 | 选择依据 |
|------|------|------|---------|
| 下层（最常用） | 视线平齐 | A E I O N R S T L | 高频出现于四年级课标词汇 |
| 中层（次常用） | 略高于视线 | B C D F G H M P U W Y | 中频字母 |
| 上层（生僻） | 需抬头/滑动视角 | J K Q V X Z | 低频字母 |

下层和中层在默认视角内全部可见；上层需要玩家向上滑动视角（滑动视角是相机控制，不计为"点击交互"）才能看到。

### 5.2 字母精灵的视觉形态

- **休眠态**：岩壁凹槽中的发光符文（大写字母形），缓慢呼吸光。
- **召唤态**：被玩家声音唤醒后，符文化为光精灵飞出，沿弧线飞向拼写槽位。
- **就位态**：停留在槽位内，以小写字母形态显示。
- **散落态**：朗读失败时，槽位中的精灵散落，沿抛物线飞回岩壁原位，短暂变暗 2 秒后恢复休眠。
- **回位态**：刻印成功后，精灵不需回位——它已"融入"石碑铭文。岩壁凹槽的符文变为永久点亮态（收集进度可视化）。

### 5.3 字母名识别机制（核心难点）

玩家通过说出**字母名**（letter name，如 /eɪ/ /biː/ /siː/）召唤字母精灵。这是本场景最大的技术风险。

**识别流程：**

```
玩家说字母名
  → VoicePipeline 录音 → ASR（Whisper）
  → HybridAPI.get_asr_corrected_text(result) 获取识别文本
  → voice-service postprocess 识别 intent = "letter_name"
    extracted.letter = 大写单字母（A-Z）
  → 客户端接收 extracted.letter，映射到字母精灵
  → 对应符文亮起，精灵飞入下一个空槽位
```

**已知识别风险（必须诚实面对）：**

Whisper 对单字母名的识别存在系统性混淆，尤其在儿童口音、非母语发音、环境噪音下：

| 易混淆字母组 | 典型混淆原因 |
|-------------|-------------|
| B / D / P / T / E / G / C / Z | 爆破音 + 前元音 /iː/ 结尾，频谱相似 |
| M / N | 鼻音相近 |
| A / 8 / H / I / Y | /eɪ/ 与数字、字母音近 |
| S / X / F | 擦音 + /e/ 或 /eks/ |
| L / R / O | 儿童发音 L/R 不分普遍 |
| V / W / Y | 半元音近似 |

**识别置信度分层处理：**

```
letter_confidence = ASR 对该字母识别的置信度（0.0-1.0）

IF letter_confidence >= letter_high_threshold (默认 0.80):
    直接采纳，精灵飞入槽位

IF letter_medium_threshold (0.55) <= letter_confidence < 0.80:
    视为模糊识别：
    - 守灵用英语复述："Did you say 'B'?"
    - 玩家说 "yes" 确认 → 采纳
    - 玩家说 "no" 或重说字母 → 重新识别
    - 最多复述确认 2 次，仍模糊则按最高置信度采纳并高亮显示（玩家可后续撤回）

IF letter_confidence < 0.55:
    视为识别失败：
    - Spark 提示："I couldn't hear the letter clearly. Try again."
    - 不填入槽位，不消耗任何资源
    - 玩家重说
```

**重复字母处理：** 目标单词含重复字母（如 "apple" 两个 p）时，玩家说两次 "P"，每次召唤一个精灵克隆飞入槽位。视觉上同一符文分裂出第二个精灵。

### 5.4 撤回与修改指令

玩家可通过语音指令修改已填入的字母：

| 指令（英语） | 作用 | 场景表现 |
|------------|------|---------|
| "undo" / "back" | 撤回最后一个填入的字母 | 最后一个槽位的精灵飞回岩壁原位 |
| "clear" / "reset" | 清空所有已填字母 | 所有槽位精灵飞回岩壁 |
| "remove <letter>" | 移除指定字母（如 "remove B"） | 该字母精灵飞回岩壁（若槽位中有多个同字母，移除最后一个） |
| "done" / "ready" / "finish" | 确认拼写完成，进入判定 | 槽位条整体发光，进入 SPELL_CONFIRM |

**指令语言策略：** 所有玩家语音指令统一用**英语**。原因：
1. 保持归卷厅"声音仪式"的沉浸感，英语指令与英语字母名、英语朗读一致。
2. 避免玩家在英语字母名和中文指令间频繁切换语言，降低认知负担。
3. 四年级学生已掌握 "undo/back/clear/done/yes/no/help/next/leave" 等基础指令词。
4. feifei 在新手引导时用中文解释这些指令的含义（§8.3），玩家学会后用英语下达。

### 5.5 字母召唤冷却

为防止 ASR 把一次发音识别为多个字母（如 "CD" 被识别为连续两个字母），每次字母召唤后有**召唤冷却**（见 §12）。冷却期间 VoicePipeline 仍监听但不采纳新字母，冷却结束后可说下一个字母。这给玩家一个清晰的节奏：一个字母一个字母说，不要连读。

**不鼓励连说多个字母。** Whisper 对快速连续说多个单字母名（如 "A-P-P-L-E"）识别率显著下降。场景设计明确引导玩家逐个字母召唤，槽位逐个填入，建立清晰的拼写节奏感。

---

## 6. 朗读与 ASR 集成点

### 6.1 阶段切换与 VoicePipeline 监听模式

归卷厅是**持续多轮语音交互**场景。VoicePipeline 在不同阶段以不同 `attempt_type` 监听，`recording_context` 随阶段变化：

| 阶段 | attempt_type | 监听目标 | 监听时长策略 |
|------|-------------|---------|-------------|
| 入口唤醒 | `wake_guardian` | 任意英语问候 | 单次监听，no-speech 10s 后 Spark 提示 |
| SPELLING | `letter_name` | 单字母名 / 指令（undo/clear/done 等） | 循环监听，每次字母识别后短暂冷却再监听 |
| SPELL_CONFIRM | （无监听） | — | 系统判定拼写，动画过渡 |
| READING | `word_pronunciation` | 目标单词发音 | 单次监听，硬上限 8s |
| JUDGING | （无监听） | — | ASR 判定中 |
| PLAYBACK_REVIEW | `playback_self_eval` | 玩家选择 "retry" / "accept" | 单次监听 |
| COMPLETE | `exit_command` | "leave" / "next" / "continue" | 循环监听 |

### 6.2 recording_context 字段（按阶段）

**入口唤醒阶段：**
```gdscript
{
    "scene_id": "word_spirit_library_archive_hall",
    "quest_id": "archive_enter",
    "content_id": "archive_entry_wake",
    "prompt_text_snapshot": "对书柜守灵说话以进入归卷厅",
    "target_utterance_snapshot": "",
    "attempt_type": "wake_guardian",
    "expected_answer_type": "open_greeting",
}
```

**拼写阶段（字母召唤）：**
```gdscript
{
    "scene_id": "word_spirit_library_archive_hall",
    "quest_id": "archive_inscribe_<word_id>",
    "content_id": "archive_letter_<word_id>_<slot_index>",
    "prompt_text_snapshot": "说一个字母召唤字母精灵",
    "target_utterance_snapshot": "<expected_letter>",
    "attempt_type": "letter_name",
    "expected_answer_type": "letter_name",
    "word_id": "<word_id>",
    "slot_index": <int>,
    "clue_type": "chinese_meaning | picture | sentence_gap | listen_spell | synonym_antonym",
}
```

**朗读阶段：**
```gdscript
{
    "scene_id": "word_spirit_library_archive_hall",
    "quest_id": "archive_inscribe_<word_id>",
    "content_id": "archive_word_<word_id>",
    "prompt_text_snapshot": "朗读单词以刻印词灵",
    "target_utterance_snapshot": "<target_word>",
    "attempt_type": "word_pronunciation",
    "expected_answer_type": "word_pronunciation",
    "word_id": "<word_id>",
    "word_text": "<target_word>",
    "clue_type": "...",
}
```

字段说明：
- `scene_id` 必须加入 `MagicEchoManager.SCENE_ID_MAP`，规范化后加入 `MagicEchoManager.LEARNING_SCENES`。
- `quest_id` / `content_id` 使用词牌对应单词 ID + 槽位索引生成，便于 LXP 追踪到字母粒度。
- `attempt_type = "letter_name"` 与 `attempt_type = "word_pronunciation"` 区分拼写阶段与朗读阶段，便于 voice-service postprocess 选择不同识别策略。
- `game_session_id` / `prompt_turn_id` 若未传，由 VoicePipeline 通过 MagicEchoManager active session 自动补齐（CLAUDE.md §3）。

### 6.3 voice_ended 后的刻印判定流程（朗读阶段）

```
VoicePipeline.voice_ended(audio_data)  [READING 阶段]
  → 场景调用 HybridAPI 请求 ASR
  → ASR 返回 result
  → 场景读取（使用 HybridAPI helper，不直接读 result.postprocess.*）：
      - corrected_text = HybridAPI.get_asr_corrected_text(result)
      - confidence = HybridAPI.get_asr_confidence(result)
  → 判定逻辑（场景控制器本地完成）：
      IF ASR 不可用 / result 为空 → 进入 PLAYBACK_REVIEW（§6.5）
      IF corrected_text 与 target_word 匹配（大小写不敏感、去标点）：
          共鸣度 = confidence
          → 清晰 (>=0.85) → 满星刻印
          → 接近 (0.65-0.84) → 部分星刻印
          → 再试 (0.40-0.64) → 不刻印，朗读重试（消耗一次朗读机会）
          → 需要帮助 (<0.40) → 不刻印，Spark 示范模式（§7.4）
      ELSE（识别文本与目标词不匹配）：
          → 视为朗读未通过，消耗一次朗读机会
  → 朗读机会耗尽（默认 2 次）→ 词牌转墨影词牌
```

### 6.4 字母召唤阶段的 voice_ended 处理

```
VoicePipeline.voice_ended(audio_data)  [SPELLING 阶段]
  → 场景调用 HybridAPI 请求 ASR
  → ASR 返回 result
  → 场景读取：
      - intent = HybridAPI.get_asr_intent(result)
      - corrected_text = HybridAPI.get_asr_corrected_text(result)
      - confidence = HybridAPI.get_asr_confidence(result)
  → 分支：
      IF intent == "letter_name" AND extracted.letter 非空：
          → 按 §5.3 置信度分层处理
      IF intent == "command":
          → 按指令映射表（§5.4、§8.1）处理 undo/clear/done/leave 等
      IF intent == "off_topic" 或 intent == "provide"（但非字母非指令）：
          → Spark 软提示："Say a letter, or say 'done' to finish."
      IF no-speech：
          → 不消耗资源，Spark 10s 后提示 "Say a letter to call a spirit."
```

### 6.5 ASR 不可用降级：录音回放 + feifei 引导

当 ASR 不可用或连续返回空结果时（主文档 §3.3 阶段 1），归卷厅降级为**录音回放 + feifei 语音引导**模式。注意：**不能降级为点击交互**——纯语音约束不可破。

```
PLAYBACK_REVIEW 阶段：
  1. VoicePipeline.voice_ended 后，场景播放录音回放给玩家听
  2. 同时播放目标单词的示范发音（TTS 预生成或缓存）
  3. feifei 用中文引导（唯一可用中文的时刻）：
     "听起来像吗？说 'retry' 再试一次，或者说 'accept' 就这样刻印。"
  4. VoicePipeline 监听玩家指令（attempt_type: "playback_self_eval"）：
     - "retry" / "again" → 重新进入 READING（消耗一次朗读机会）
     - "accept" / "ok" / "yes" → 以减半星星刻印（主文档 §3.3：星星减半）
  5. 朗读机会耗尽 → 词牌转墨影词牌
```

降级模式必须仍然：
- 保留 InteractionAttempt 和 timeline event（CLAUDE.md §4）
- 不上传无效音频文件
- no-speech 走 CLAUDE.md §4 的 no-speech 记录链路

### 6.6 录音流程合规检查清单

归卷厅场景控制器**不得**自实现以下逻辑（CLAUDE.md §2、§5、§6）：

- [ ] 不自实现录音硬上限停止逻辑（由 VoicePipeline.max_duration_reached 处理）
- [ ] 不自实现 BGM/SFX/TTS duck begin/end（由 VoicePipeline 在 start_listening / voice_ended / max_duration_reached 时成对处理）
- [ ] 不直接读 result.postprocess.*（统一用 HybridAPI.get_asr_* helper）
- [ ] no-speech 不绕过底层记录链路（保留 InteractionAttempt + timeline event）
- [ ] 所有提前 return / 错误分支都确保 duck end 已被 VoicePipeline 处理（场景不调用 duck）

场景只负责：
- 按阶段调用 VoicePipeline.start_listening(recording_context)
- 在 voice_ended 信号回调中调用 ASR
- 根据 ASR 结果推进阶段状态机

---

## 7. 反馈与奖励表现

### 7.1 刻印成功表现

```
触发：朗读通过（清晰/接近）
1. 石碑中央光环爆亮 → 字母精灵从槽位融入石碑表面
2. 铭文逐字发光刻入石碑（每字 80ms 延迟，营造刻写感）
3. 刻印完成音效（清脆的"叮"声 + 轻微石质回响）
4. 星星从铭文飞出，沿弧线飞向屏幕顶部星星条
   - 清晰：3 颗星（满星）
   - 接近：2 颗星（部分星）
5. Spark 飞近石碑，英语鼓励语（§8.5）
6. 守灵提示："Say 'next' to continue, or 'leave' to exit."
7. VoicePipeline 进入 COMPLETE 阶段监听
```

### 7.2 刻印失败表现

```
触发：朗读未通过且朗读机会耗尽
1. 石碑光环变暗、闪烁
2. 槽位中的字母精灵散落，沿抛物线飞回岩壁原位
3. 散落音效（轻柔的"沙"声，不是错误蜂鸣——避免挫败感）
4. 词牌变暗、边缘出现墨色晕染 → 飞入墨影词牌区
5. Spark 软反馈："The word spirit slipped away. We'll try again later."
6. feifei 仅在连续 2 张墨影词牌后用中文轻声引导（§8.3）
7. 词牌架自动浮起下一张词牌
```

### 7.3 星星奖励规则

| 朗读结果 | 星星 | 刻印状态 |
|---------|------|---------|
| 清晰（>=0.85） | 3 星 | 满星刻印，铭文金色发光 |
| 接近（0.65-0.84） | 2 星 | 部分星刻印，铭文银色发光 |
| 录音回放自评接受 | 1 星 | 减半刻印，铭文微光 |
| 再试 / 需要帮助（未耗尽机会） | 0 星（不计入） | 不刻印，重试 |
| 朗读机会耗尽 | 0 星 | 墨影词牌，不刻印 |

星星发放通过 Star Economy 系统的 `stars_per_response` 接口，本场景不自行定义星星计算公式。

### 7.4 连续失败时 Spark 示范模式

```
触发条件：
  - 同一词牌朗读连续 2 次未通过（再试 / 需要帮助）
  - 或同一词牌拼写连续 2 次错误

Spark 示范模式表现：
  1. Spark 飞近石碑，字母岩壁变暗
  2. Spark 逐字母点亮目标单词的字母精灵（岩壁上对应符文依次亮起）
  3. 每点亮一个字母，播放该字母的发音
  4. 全部点亮后，播放完整单词的示范发音
  5. Spark 英语鼓励："Now let's say it together."
  6. 自动进入 READING 阶段，不计入朗读机会消耗
  7. 此次朗读若通过，仍可刻印，但星星减半（示范后刻印为 1 星封顶）

退出条件：
  - 示范后朗读通过 → 刻印（1 星）
  - 示范后朗读仍未通过 → 词牌转墨影词牌
```

### 7.5 墨影词牌区表现

- 墨影词牌以暗色卷轴形态堆叠在场景左下角暗格。
- 每张墨影词牌显示一行低负担例句或图像线索。
- 墨影词牌数量过多时（超过 5 张），feifei 用中文提示引导自然停止（§8.3）。

---

## 8. 整体语音指令集

### 8.1 玩家语音指令一览

所有玩家指令统一用**英语**。feifei 在新手引导时用中文解释含义。

| 指令（英语） | 可用阶段 | 作用 | 场景响应 |
|------------|---------|------|---------|
| "hello" / "hi" / "guardian" / "open" / "archive" | 入口唤醒 | 唤醒书柜守灵 | 守灵现身，进入归卷厅 |
| "<letter name>"（A-Z） | SPELLING | 召唤对应字母精灵 | 精灵飞入槽位 |
| "undo" / "back" | SPELLING | 撤回最后一个字母 | 末位精灵飞回岩壁 |
| "clear" / "reset" | SPELLING | 清空所有已填字母 | 所有精灵飞回岩壁 |
| "remove <letter>" | SPELLING | 移除指定字母 | 该字母精灵飞回 |
| "done" / "ready" / "finish" | SPELLING | 确认拼写完成 | 进入 SPELL_CONFIRM |
| "retry" / "again" | READING / PLAYBACK_REVIEW | 重试朗读 | 重新进入 READING |
| "accept" / "ok" / "yes" | PLAYBACK_REVIEW | 接受录音回放自评 | 减半星星刻印 |
| "help" / "hint" | 任意玩法阶段 | 请求 Spark 帮助 | Spark 示范模式或提示 |
| "next" | COMPLETE / 词牌间 | 进入下一张词牌 | 词牌架浮起下一张 |
| "leave" / "exit" / "stop" / "quit" | 任意阶段 | 退出归卷厅 | 守灵确认后退出 |
| "yes" / "no" | 退出确认 | 响应守灵退出确认 | 确认/取消退出 |

### 8.2 指令识别策略

- voice-service postprocess 负责将 ASR 文本分类为 `letter_name` / `command` / `provide` / `off_topic` / `delegate` 五种 intent。
- `command` intent 下，extracted.command 字段返回标准化指令词（undo/clear/done/leave/help/next/retry/accept/yes/no）。
- 客户端按 §5.4、§8.1 指令映射表处理。
- 未识别为已知指令的英语短语：视为 off_topic，Spark 软提示当前阶段可用指令。
- 指令识别允许模糊匹配（如 "don" / "dun" 也映射到 "done"），由 voice-service postprocess 负责。

### 8.3 feifei 新手引导（中文，唯一可说中文的 NPC）

feifei 在以下时刻用中文解释规则与指令含义，保持克制：

- **首次进入归卷厅**（一次性）："这是归卷厅。石碑上还空着——我们要用声音召唤字母精灵，把学过的单词刻上去。说一个字母名，比如 'A'，对应的精灵就会飞过来。拼完所有字母后，说 'done' 确认。"
- **首次拼写阶段**（一次性，若玩家 10s 未说话）："说一个字母名试试，比如 'A'。"
- **首次朗读阶段**（一次性）："拼好了！现在对着石碑，把这个词读出来。"
- **首次撤回**（一次性，玩家说 "undo" 后）："嗯，最后一个字母飞回去了。"
- **连续 2 张墨影词牌**："没关系，有些词灵比较害羞。我们先刻下一个，它待会儿就回来了。"
- **墨影词牌过多**（>5）："今天有好多词灵藏起来了，明天我们再来找它们吧。"
- **ASR 不可用降级时**："听起来像吗？说 'retry' 再试一次，或者说 'accept' 就这样刻印。"

### 8.4 书柜守灵对白方向（仅英语）

守灵性格：沉稳、古老、友善，像一个老书匠。语气简短。

- **入口迎接**："Welcome back. The word spirits are waiting to be inscribed."
- **退出确认**："Some word spirits are still waiting. Leave anyway?"
- **完成报告**："Today's inscription is complete. <N> word spirits now rest in the stone. Well done."
- **无词牌可刻**："The stone is quiet today. Come back tomorrow for new word spirits."
- **字母模糊确认**（§5.3）："Did you say '<letter>'?"

### 8.5 Spark 对白方向（仅英语）

Spark 在归卷厅内统一用英语，保持"魔法伙伴"语气。

- **刻印成功（清晰）**："Perfect! The word spirit is now in the stone."
- **刻印成功（接近）**："Good! The word spirit heard you."
- **朗读再试**："Almost! Try once more."
- **示范模式触发**："Let me help. Watch the letters, then say it with me."
- **拼写错误**："Not quite. Say 'undo' to fix a letter, or 'clear' to start over."
- **字母识别失败**："I couldn't hear the letter clearly. Try again."
- **沉默提示**："Say a letter to call a spirit." / "Now say the word."

### 8.6 对白系统接入

- 书柜守灵、Spark、feifei 的对白通过 DialogueSystem 驱动，不在场景控制器中硬编码台词。
- 对白流程文件位于 `assets/resources/dialogue_flows/word_spirit_library_archive_hall.json`。
- 鼓励语模板复用 `assets/resources/dialogue/encouragement_templates.json`。

---

## 9. 状态与存档接口

### 9.1 读取的状态

| 状态来源 | 字段 | 用途 |
|---------|------|------|
| `MagicEchoManager` | `active_game_session_id` | 绑定录音 InteractionAttempt |
| `MagicEchoManager` | `active_prompt_turn_id` | 绑定录音 PromptTurn |
| `GameManager.load_progress()` | `learned_words[]` | 决定哪些单词可进入归卷厅 |
| `GameManager` | `word_mastery{word_id: mastery_level}` | 决定词牌抽取比例 |
| LXP Assessment | `recent_errors[]` | 25% 错词来源 |
| LXP Assessment | `forgetting_curve_words[]` | 60% 复习词来源 |
| Star Economy | `current_scene_stars`, `scene_threshold` | 星星条显示、Badge 解锁判断 |
| `GameManager` | `ink_shadow_queue[]` | 墨影词牌队列（跨会话保留） |

### 9.2 写入的状态

| 写入目标 | 字段 | 时机 |
|---------|------|------|
| `MagicEchoManager` | `InteractionAttempt`（每次录音：字母/朗读/指令） | `voice_ended` 后 |
| `MagicEchoManager` | `timeline_event`（含 no-speech） | 录音开始/结束/no-speech |
| `MagicEchoManager` | `pending_recording_envelope` | 录音前创建，成功后上传 |
| LXP Assessment | `word_mastery_update{word_id, delta}` | 刻印成功后 |
| LXP Assessment | `error_record{word_id, error_type}` | 墨影词牌生成时 |
| LXP Assessment | `letter_recognition_record{word_id, letter, confidence}` | 字母识别后（用于评估字母发音掌握度） |
| Star Economy | `stars_accumulated{scene_id, delta, lxp_source}` | 刻印成功后 |
| `GameManager.save_progress()` | `ink_shadow_queue[]` | 墨影词牌生成时 |
| `GameManager.save_progress()` | `archive_hall_progress{current_word_index, completed_words[]}` | 每张词牌完成后 |

### 9.3 场景控制器与 autoload 的边界

归卷厅场景控制器**只读 autoload 状态、不改变 autoload 状态**（CLAUDE.md §12）。业务状态变化由对应 manager 负责。场景控制器维护的本地状态仅限：阶段状态机、当前词牌、拼写槽位、朗读机会计数、本场景星星计数、字母召唤冷却计时。

### 9.4 崩溃恢复

遵循 CLAUDE.md §10：默认自动读档。归卷厅进入时：

1. `GameManager.load_progress()` 恢复 `archive_hall_progress`。
2. 若有未完成的词牌，从该词牌恢复。
3. 若恢复时处于 READING 阶段，回退到 SPELLING 阶段重新确认拼写（避免恢复到录音中途状态）。
4. `MagicEchoManager.reconcile_local_recordings()` 清理孤儿 pending envelope。

---

## 10. 边缘情况场景化处理

### 10.1 字母识别相关（纯语音新增）

| 情况 | 处理 |
|------|------|
| ASR 把 "B" 识别成 "D"（置信度高） | 直接采纳错误字母飞入槽位；玩家可见槽位是 D，说 "undo" 撤回，重说 "B"。视觉反馈让玩家自我纠错。 |
| ASR 把 "B" 识别成 "D"（置信度中 0.55-0.80） | 守灵复述确认："Did you say 'D'?" 玩家说 "no"，重说。 |
| ASR 字母置信度低（<0.55） | 不填入槽位，Spark 提示 "I couldn't hear the letter clearly. Try again." 不消耗资源。 |
| 玩家说中文拼音字母名（如 "bi"） | voice-service postprocess 不识别为 letter_name intent，视为 off_topic；feifei 提示："用英语说字母名，比如 'B'。" |
| 玩家连说多个字母（"A-P-P"） | 召唤冷却机制使第一个字母采纳后冷却期内忽略后续；Spark 提示 "One letter at a time." |
| 玩家说字母音而非字母名（如 "buh" for B） | voice-service postprocess 尝试映射 phonics 音到字母（通过音素匹配）；若无法映射，视为 off_topic，feifei 提示 "说字母名，比如 'B'。" |
| 玩家说数字 "8" 被识别为字母 | voice-service postprocess 区分数字与字母；若混淆，走置信度分层处理 |
| 目标单词含重复字母（"apple" 两个 p） | 玩家说两次 "P"，每次召唤一个精灵克隆飞入槽位 |

### 10.2 指令识别相关

| 情况 | 处理 |
|------|------|
| 玩家说未知指令（如 "delete"） | 视为 off_topic，Spark 提示当前阶段可用指令："Say 'undo', 'clear', or 'done'." |
| 玩家说中文指令（如 "撤回"） | voice-service 识别为中文，视为 off_topic；feifei 提示："说 'undo' 可以撤回最后一个字母。" |
| 玩家在 READING 阶段说 "undo" | READING 阶段不接受拼写指令，Spark 提示 "Say the word now, or 'help'." |
| 玩家说 "leave" 但有未完成词牌 | 守灵确认 "Some word spirits are still waiting. Leave anyway?"，等待 yes/no |

### 10.3 拼写反复失败

| 情况 | 处理 |
|------|------|
| 拼写错误 1 次（玩家说 "done" 但拼写不对） | 退回 SPELLING，不消耗朗读机会，Spark："Not quite. Say 'undo' to fix a letter." |
| 拼写连续 2 次错误 | Spark 示范模式（§7.4）：逐字母点亮 + 示范发音，不扣星 |
| 示范后拼写仍错误 | 自动填入正确字母（每个字母精灵自动飞入槽位），进入 READING，此次刻印封顶 1 星 |
| 玩家长时间不说话（>silence_prompt_delay_s） | Spark 软提示当前阶段该说什么 |

### 10.4 朗读反复不通过

| 情况 | 处理 |
|------|------|
| 朗读第 1 次未通过 | 不刻印，消耗 1 次朗读机会，Spark："Almost! Try once more." |
| 朗读第 2 次未通过（默认 2 次机会） | Spark 示范模式（§7.4），示范后朗读不计入机会 |
| 示范后朗读仍未通过 | 词牌转墨影词牌，进入下一张 |
| no-speech（未检测到语音） | 不消耗朗读机会（CLAUDE.md §4），保留 InteractionAttempt + timeline event，Spark："I couldn't hear you. Say it again?" |

### 10.5 ASR 不可用降级

| 情况 | 处理 |
|------|------|
| ASR 服务不可达 | 自动进入 PLAYBACK_REVIEW（§6.5），录音回放 + 示范发音对比，feifei 中文引导玩家说 "retry"/"accept" |
| ASR 连续返回空结果 3 次 | 同上降级 |
| ASR 置信度极低（<0.3） | 视为未通过朗读，但不计入"连续失败"计数（避免 ASR 不稳定误触发示范模式） |
| 录音硬上限触发 | VoicePipeline.max_duration_reached 处理，场景收到信号后视为本次朗读结束，按 no-speech 或低置信度处理 |

### 10.6 玩家中途退出

| 情况 | 处理 |
|------|------|
| 主动语音退出（"leave"） | 守灵确认后保存 archive_hall_progress，未完成词牌保留为"待刻印"，次日刷新 |
| 异常退出（崩溃） | 下次进入自动恢复（§9.4），从最近完成的词牌之后继续 |
| 退出时有 pending upload | MagicEchoManager 保留 pending envelope，下次启动 reconcile_local_recordings() 处理 |

### 10.7 环境噪音

| 情况 | 处理 |
|------|------|
| 背景噪音 >60dB | Spark 提示 "Let's find a quieter place."，暂停当前监听，等待玩家移动到安静环境后自动恢复 |
| 持续噪音导致连续 no-speech 3 次 | feifei 中文提示："太吵了，换个安静的地方再说吧。" 暂停监听，玩家可说 "resume" 恢复 |

### 10.8 词牌池异常

| 情况 | 处理 |
|------|------|
| 当日无可刻印词牌 | 守灵："The stone is quiet today. Come back after learning new words." 不进入玩法循环 |
| 词牌池全部完成 | 进入 COMPLETE，守灵播放完成语 + 刻印报告 |
| 墨影词牌堆积过多（>5） | feifei 引导自然停止（§8.3） |
| 某个单词 mastery 已满 | 该单词不再进入词牌池 |

---

## 11. 可访问性与儿童体验

纯语音对四年级学生（9-10 岁）的注意力和发音要求更高。以下设计确保玩家始终知道该说什么、说了之后会发生什么。

### 11.1 清晰的语音提示反馈循环

每个阶段都有**三层提示**，确保玩家不迷失：

1. **视觉焦点高亮**（§4.5）：当前可交互区域泛光，其他区域变暗。
2. **Spark 语音提示**：进入新阶段时 Spark 用英语说一句该做什么（"Say a letter to call a spirit." / "Now say the word."）。
3. **feifei 中文兜底**（仅必要时）：玩家连续 2 次无响应或连续失败时，feifei 用中文解释。

### 11.2 沉默处理

玩家沉默是纯语音场景最常见的"卡住"原因。分级处理：

| 沉默时长 | 响应 |
|---------|------|
| 5s | 麦克风指示器轻微脉冲（视觉提示） |
| 10s | Spark 英语提示当前阶段该说什么 |
| 15s | feifei 中文提示（若仍在 SPELLING/READING） |
| 30s | 守灵提示 "Say 'leave' if you want to stop for today." 给玩家退出选项 |

沉默不消耗任何资源，不扣星，不计入失败次数。

### 11.3 字母名学习支持

四年级学生可能不熟悉所有字母名（letter name）的英语发音。提供学习支架：

- 首次进入 SPELLING 阶段时，feifei 用中文一次性提示："说字母名，比如 'A'、'B'、'C'。"
- 玩家说 "help" 时，Spark 逐个点亮目标单词的字母符文并播放字母名发音（示范模式）。
- 字母岩壁的符文上始终显示字母形（大写字母视觉），玩家看见形即可联想到名。

### 11.4 节奏控制

纯语音容易疲劳。归卷厅通过以下方式控制节奏：

- 每张词牌完成后有 2-3 秒的视觉过渡（铭文留驻、星星飞出），给玩家喘息。
- 完成 5 张词牌后，feifei 主动提示："休息一下，喝口水再继续。"（不强制停止，玩家可说 "next" 继续）。
- 每日词牌数默认 10 张，对齐 8-10 分钟标准会话时长。

### 11.5 正面反馈优先

纯语音场景中，玩家容易因识别失败而挫败。所有反馈遵循正面优先：

- 识别失败不是"错误"，是"没听清"（Spark："I couldn't hear clearly."）。
- 散落动画用轻柔音效，不用错误蜂鸣。
- 墨影词牌不是"失败"，是"词灵藏起来了"（feifei："词灵比较害羞"）。
- 任何阶段玩家都可说 "help" 获得示范，不扣星。

---

## 12. 调参旋钮

所有旋钮存入 `assets/data/word_spirit_library_scene.json`，不硬编码。

| 参数 | 默认值 | 范围 | 类别 | 理由 |
|------|--------|------|------|------|
| `daily_word_cards` | 10 | 6-15 | Gate | 每日词牌数量，对齐主文档 vocabulary_words_per_day |
| `reading_retry_limit` | 2 | 1-3 | Feel | 朗读重试上限 |
| `spell_error_retry_limit` | 2 | 1-3 | Feel | 拼写连续错误触发示范模式的阈值 |
| `letter_high_threshold` | 0.80 | 0.70-0.90 | Curve | 字母识别高置信度阈值，直接采纳 |
| `letter_medium_threshold` | 0.55 | 0.45-0.65 | Curve | 字母识别中置信度阈值，需守灵复述确认 |
| `letter_summon_cooldown_ms` | 600 | 400-1000 | Feel | 字母召唤冷却，防止连说识别堆积 |
| `letter_fly_duration_ms` | 350 | 200-600 | Feel | 字母精灵飞入槽位动画时长 |
| `inscribe_char_delay_ms` | 80 | 40-150 | Feel | 铭文逐字刻入延迟 |
| `scatter_fly_duration_ms` | 500 | 300-800 | Feel | 散落动画时长 |
| `show_target_word_during_reading` | false | true/false | Feel | 朗读阶段是否显示目标词文字（默认隐藏） |
| `reading_max_duration_s` | 8 | 5-15 | Gate | 朗读录音硬上限，由 VoicePipeline 强制 |
| `letter_max_duration_s` | 3 | 2-5 | Gate | 字母召唤单次监听硬上限 |
| `silence_to_spark_prompt_s` | 10 | 5-15 | Gate | 沉默多久触发 Spark 英语提示 |
| `silence_to_feifei_prompt_s` | 15 | 10-25 | Gate | 沉默多久触发 feifei 中文提示 |
| `silence_to_exit_option_s` | 30 | 20-45 | Gate | 沉默多久提示玩家可退出 |
| `noise_pause_threshold_db` | 60 | 50-70 | Feel | 触发噪音暂停的阈值 |
| `consecutive_no_speech_to_feifei` | 3 | 2-5 | Gate | 连续 no-speech 多少次触发 feifei 换环境提示 |
| `ink_shadow_soft_cap` | 5 | 3-8 | Gate | 墨影词牌堆积上限 |
| `mastery_max_to_reenter` | 3 | 2-5 | Curve | 单词 mastery 达到此值后不再进入词牌池 |
| `demonstration_star_cap` | 1 | 1-2 | Curve | 示范模式后刻印的星星封顶 |
| `playback_review_star` | 1 | 1-2 | Curve | 录音回放自评接受时的星星数（减半） |
| `scene_id` | "word_spirit_library_archive_hall" | — | — | 场景标识 |
| `rest_prompt_every_n_cards` | 5 | 3-8 | Gate | 每完成 N 张词牌 feifei 提示休息 |

---

## 13. 验收标准

### 13.1 功能验收

- [ ] 玩家能通过对书柜说话唤醒书柜守灵并进入归卷厅（RPG 行为：语音唤醒），不是点击/触摸。
- [ ] 归卷厅能根据 learned_words / word_mastery / recent_errors / forgetting_curve_words 生成当日词牌池，且词牌对应单词均为玩家已学过的单词。
- [ ] 玩家说出字母名后，对应字母精灵飞入拼写槽位；字母识别按 §5.3 置信度分层处理（高置信度直接采纳、中置信度守灵复述确认、低置信度提示重说）。
- [ ] 玩家说 "undo"/"clear"/"done" 等英语指令能正确执行撤回/清空/确认。
- [ ] 拼写正确后进入朗读阶段，拼写错误只退回拼写阶段、不消耗朗读机会。
- [ ] 朗读阶段调用 VoicePipeline.start_listening(recording_context)，recording_context 的 attempt_type 为 "word_pronunciation"，包含 §6.2 所列字段。
- [ ] 拼写阶段调用 VoicePipeline.start_listening(recording_context)，attempt_type 为 "letter_name"。
- [ ] voice_ended 后通过 HybridAPI.get_asr_* helper 读取 ASR 结果，不直接读 result.postprocess.*。
- [ ] 朗读通过（清晰/接近）可将单词刻印到石碑并发放星星；朗读未通过且机会耗尽则词牌转墨影词牌。
- [ ] ASR 不可用时降级为录音回放 + feifei 语音引导（玩家说 "retry"/"accept"），仍可刻印（星星减半），不降级为点击交互。
- [ ] no-speech 不上传音频文件，保留 InteractionAttempt + timeline event，不消耗朗读机会、不消耗字母召唤资源。
- [ ] 录音硬上限由 VoicePipeline.max_duration_reached 处理，场景不自实现停止逻辑。
- [ ] BGM/SFX/TTS duck 由 VoicePipeline 成对处理，场景所有提前 return / 错误分支不漏 duck end。
- [ ] 连续 2 次拼写错误或朗读未通过触发 Spark 示范模式（逐字母点亮 + 示范发音）。
- [ ] 玩家说 "leave" 能触发退出流程，守灵确认后保存 archive_hall_progress。
- [ ] 中途退出保存 archive_hall_progress，下次进入从最近完成词牌之后恢复。
- [ ] 崩溃恢复走 GameManager.load_progress() + MagicEchoManager.reconcile_local_recordings()，不默认关闭自动读档。
- [ ] pending upload 徽标从 MagicEchoManager.get_pending_uploads() 派生，UI 不维护自己的计数。

### 13.2 体验验收

- [ ] 测试玩家（9-10 岁）理解"用声音召唤字母精灵、朗读刻印"是 RPG 行为，不是英语练习页。
- [ ] 测试玩家在任何阶段都知道该说什么（视觉焦点高亮 + Spark 语音提示 + feifei 中文兜底三层提示）。
- [ ] 测试玩家沉默 10s 内收到 Spark 英语提示，15s 内收到 feifei 中文提示，不会"卡住不知道干嘛"。
- [ ] 测试玩家说错字母（如 B 说成 D）能通过视觉反馈发现并说 "undo" 撤回重说。
- [ ] 测试玩家理解朗读失败不是"被批评"，而是"词灵没听清"。
- [ ] 连续失败时测试玩家不会卡死在单张词牌上（示范模式兜底）。
- [ ] 测试玩家能在 8-10 分钟内完成标准每日词牌池（10 张）。
- [ ] 测试玩家愿意次日回来继续刻印（墨影词牌提供回来理由，不制造挫败）。
- [ ] 书柜守灵、Spark 的英语台词对四年级学生可理解（用词简单、语速适中、TTS 清晰）。
- [ ] feifei 的中文引导只在必要时刻出现（首次、连续失败、自然停止、ASR 降级），不频繁打断。

### 13.3 字母识别专项验收

- [ ] 在安静环境下，常用字母（A E I O N R S T L）识别准确率 >= 85%（儿童口音）。
- [ ] 易混淆字母对（B/D, M/N, E/G/C）在置信度分层处理下，误采纳率 <= 10%。
- [ ] 字母召唤冷却有效防止连说识别堆积（玩家说 "ABC" 只采纳第一个字母）。
- [ ] 守灵复述确认机制在中置信度场景下正常工作（"Did you say 'B'?" → yes/no）。
- [ ] 玩家说中文拼音字母名（如 "bi"）不被误识别为字母 B，而是触发 feifei 引导用英语说字母名。

### 13.4 合规验收（CLAUDE.md 对齐）

- [ ] 场景 controller 不自实现录音硬上限停止逻辑（§2）。
- [ ] recording_context 包含完整字段，game_session_id/prompt_turn_id 可由 MagicEchoManager 自动补齐（§3）。
- [ ] no-speech 走底层记录链路（§4）。
- [ ] 录音硬上限从 start_listening() 后开始计算，到上限后停麦克风/清 buffer/结束 duck（§5、§6）。
- [ ] ASR 结果统一通过 HybridAPI helper 读取（§7）。
- [ ] 委托意图（letter_name / command intent）由客户端处理，voice-service 只识别 intent（§8）。
- [ ] candidate_answers 不用于开放姓名/自由回答（§9）。
- [ ] 默认 test_mode_skip_auto_load_save=false（§10）。
- [ ] 切场景不在 _ready() 中直接抢切，用 call_deferred（§11）。
- [ ] UI 显示状态来自系统真实状态，不维护自己的计数（§12）。

### 13.5 性能验收

- [ ] 场景加载 < 2 秒。
- [ ] 字母精灵飞行动画 60fps（使用 Tween）。
- [ ] 字母名识别端到端响应 < 2 秒（P95，从 voice_ended 到精灵飞入）。
- [ ] 朗读识别端到端响应 < 3 秒（P95）。
- [ ] 持续多轮监听不导致内存泄漏（VoicePipeline 状态正确重置）。

---

## 附录 A: 场景文件清单（实现参考）

| 文件 | 类型 | 说明 |
|------|------|------|
| `assets/scenes/WordSpiritLibraryArchiveHall.tscn` | 场景 | 归卷厅主场景 |
| `assets/scripts/scenes/WordSpiritLibraryArchiveHallController.gd` | 控制器 | 阶段状态机 + 语音交互逻辑 |
| `assets/scenes/WordSpiritLibraryBookshelfEntry.tscn` | 场景 | 书柜入口（嵌入书阁大厅） |
| `assets/resources/dialogue_flows/word_spirit_library_archive_hall.json` | 对白流程 | 守灵/Spark/feifei 对白 |
| `assets/data/word_spirit_library_scene.json` | 数据配置 | 所有调参旋钮 |
| `assets/resources/word_cards/` | 词牌资源 | 按单词 ID 组织的词牌线索资源 |

本附录为实现建议，最终文件位置由 gameplay-programmer 与 godot-specialist 确认。

---

## 附录 B: 纯语音交互的技术风险与缓解

| 风险 | 严重度 | 缓解策略 |
|------|--------|---------|
| Whisper 单字母识别准确率低 | 高 | 置信度分层 + 守灵复述确认 + 视觉反馈让玩家自我纠错 |
| 易混淆字母对（B/D/M/N）误识别 | 高 | 中置信度走复述确认；玩家可 "undo" 撤回；letter_recognition_record 上报用于后续模型优化 |
| 儿童发音不标准（L/R 不分） | 中 | 接受母语口音，置信度阈值宽松；示范模式兜底 |
| 环境噪音干扰 | 中 | 噪音检测 + Spark 提示换环境 + 暂停监听 |
| 玩家不知道该说什么 | 中 | 三层提示（视觉焦点 + Spark 英语 + feifei 中文）+ 沉默分级响应 |
| ASR 服务不可用 | 中 | 降级为录音回放 + feifei 语音引导，不降级为点击 |
| 连续说多个字母识别堆积 | 低 | 召唤冷却机制 + Spark 提示 "One letter at a time" |
| 玩家说中文指令 | 低 | 视为 off_topic，feifei 引导用英语指令 |

**诚实声明：** 纯语音字母识别在当前 ASR 技术下无法做到 100% 准确。本设计通过置信度分层、复述确认、视觉反馈自我纠错、撤回指令、示范模式兜底等多层机制，将识别错误对玩家体验的影响降到可接受范围。上线后应持续监控 `letter_recognition_record` 数据，优化 voice-service 的字母识别模型。

---

## 附录 C: 与父文档的对齐说明

本场景文档与 `word-spirit-library.md` §3.3 归卷厅的对齐关系：

| 父文档规则 | 本场景落地 |
|-----------|-----------|
| 词牌给出中文/图片/例句线索 | §4.4 词牌线索呈现 |
| 召唤字母精灵拼出目标单词 | §5 字母精灵召唤（纯语音：说字母名） |
| 朗读单词 → ASR 判定 | §6 朗读与 ASR 集成点 |
| 通过刻印到石碑，获得星星 | §7.1、§7.3 |
| 失败字母散落，词牌变墨影词牌 | §7.2、§7.5 |
| 拼写错误只退回拼写阶段，不消耗朗读机会 | §10.3 |
| 朗读不通过才转墨影词牌 | §10.4 |
| 无 ASR 时录音回放自评（星星减半） | §6.5（不降级为点击，只降级为录音回放 + feifei 引导） |
| 接入 ASR 后用共鸣度判定 | §6.3、§7.3 |
| 朗读只针对单词本身 | §6.2 attempt_type = "word_pronunciation" |
| 常用字母易触达，生僻字母需主动寻找 | §5.1 空间分布（视觉易见 + 语音呼唤） |
| 连续失败 Spark 示范模式 | §7.4 |

**本版本（0.2）相对 0.1 的主要变更：** 全面改为纯语音交互，移除所有点击/键盘输入；新增字母名识别机制（§5.3）、整体语音指令集（§8）、字母识别边缘情况（§10.1）、可访问性与儿童体验（§11）、字母识别专项验收（§13.3）、技术风险与缓解附录（附录 B）。
