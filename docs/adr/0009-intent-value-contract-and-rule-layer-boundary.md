# 目标意图判定的取值契约与规则层边界（intent 扩五值 + 判据字段）

## 状态

accepted（2026-09-16）。裁定已齐（`rule_001`–`rule_011`，见 `services/voice-service/tests/intent_eval/rulings.jsonl`；实现期又补了 `rule_012`/`rule_013`——两条都是**收窄**规则层权限的修正，见 §10），**实现已落**：规则层模块 `src/services/intent_rules.py` 已接入 `ASRPostprocessor.process()`，判据字段随响应发出，`intent` 已扩到五值（`IntentLabel`）。完成的判据见文末「后果 · 定义完成」。

## 背景

voice-service 的目标意图判定（`target_intent` / `intent_description` / `expected_slots` / `candidate_answers` → `intent` / `extracted`）现状是**单次 LLM 一次性出结论**：规则说明全在 system prompt 里（`src/services/asr_postprocess.py:_system_prompt`），拿回 JSON 后只做轻量过滤。这条链路既没有确定性校验层，也没有判据字段。

首次建立度量后（`docs/plans/2026-09-15-intent-accuracy.md`），实测暴露的问题都不是"模型不够聪明"，而是**口径没定**：

| 现象 | 实测证据 |
|---|---|
| 同一份 prompt 下规范化行为不一致 | `cs_007`「我们启程吧」→「启程」；`cs_009`「接着走」→ 整段原话（5 次全错） |
| 非候选值进记录 | `cs_040`/`cs_058`：模型在"返回候选 / 返回整句"之间翻转 |
| 学习错误被改写成满分答案 | `cs_044`「Nice meet you」、`cs_045`「Meet you nice」、`cs_061` 均被修复成正确句子 |
| 迟疑句被当作确认 | `cs_065`「Let's go... 等一下」、`cs_066`「出发，等一下」均判 `provide` |
| 标签粒度不够用，客户端被迫自建影子实现 | 无 `reject`/`accept` → `BeginningFPController.gd` 自建 `DECLINE_MARKERS_EN/ZH`；无字母/指令标签 → `WordSpiritLibraryArchiveHallController.gd` 本地分类 |

11 条裁定逐条定下了**取值口径**，但这些口径目前只活在裁定文件与用例里，没有契约承载：`intent` 只有三值、判决来自规则层还是模型不可辨、判据不可复核。本 ADR 把它们固化成契约。

与 ADR-0001 的关系：**不推翻**其"识别在 voice-service、完成在前端；voice-service 无状态、不造值"的分工。本 ADR 只补两件事：取值口径，以及规则层与模型的**权限边界**。

## 决策

### 1. 权限边界：规则层是取值规范化器，不是意图裁判（`rule_003`）

- **意图判定归模型**，规则层不得覆盖。两个"绝不"：
  - 绝不因为"玩家句中出现候选"就把 `off_topic` 翻成 `provide` —— `cs_025`「我不想出发」句中含有候选「出发」，翻过来就是把否定句误判成接受（F1）。
  - 绝不因为"规则层确认不了命中"就改判 `off_topic` —— 那会把答对的孩子判成没作答（F2）。
- 规则层的产出有两种：**收窄取值**（能确认命中时改写 `extracted`，标 `verdict_source="rule"`）或**弃权**（确认不了就清空 `extracted`，保留模型的 `intent`，标 `verdict_source="llm"`，客户端自动退回 `corrected_text`）。

**唯一的例外：两处窄口径"合法性归一"（2026-09-16 裁定入契约）**

上面两个"绝不"管的是**意图推断**；以下两处不是推断，而是"该标签在当前上下文**没有消费者**"的合法性修正。收窄原则是硬的：

> **规则层只能把"没有消费者的意图"降级为 `off_topic`；绝不能把 `off_topic` 升级成任何标签。**

降级是保守方向（客户端只需重问一次，可逆），升级则可能把"没作答"伪装成能推进的意图。允许的归一只有这两条，且必须各自带 `matched_rule`：

| 归一 | `matched_rule` | 依据 | 为什么模型做不到 |
|---|---|---|---|
| 未声明 `delegatable` 的槽位上，`delegate` → `off_topic` | `delegate_requires_delegatable` | `rule_005`：没有可委托槽位就没有完成器，客户端只能当"没作答"处理 | 实测模型按**句子形态**判（同一句「随便选一个」在两种槽位上输出相同） |
| 命中候选之后紧跟撤回性内容，`provide` → `off_topic` | `retraction_after_target` | `rule_010`：迟疑不算确认；判 provide 会直接切场景（不可逆） | 实测模型把口令当命中就收工，不看后面的撤回（`cs_065`/`cs_066`） |
| 没有槽位处于提议态时，`accept`/`reject` → `off_topic` | `proposal_label_requires_proposed` | `rule_014`：没有提议可表态时这两个标签**没有消费者**（客户端只在 PROPOSED 分支读它们，其它状态下按"没作答"处理） | 实测扩五值后模型对『再换一个』（封闭题）输出 `reject`，而该例裁定结论是 `off_topic`；提示词已写明约束仍约束不住 |

实现上由 `RuleOptions(intent_vetoes=True)` 控制，**默认开启**；置 `False` 可回到纯规则_003 模式（评测回放器用两种模式并列对比，`strict` 模式保留为对照）。新增归一必须走 ADR 修订，不得就地扩表（第三条即按此流程于 2026-09-16 入表）。

### 2. 意图标签扩至五值

`intent`：`provide` / `delegate` / `off_topic` / **`accept`** / **`reject`**。

- `accept`：PROPOSED 态下玩家接受 NPC 的提议；`reject`：拒绝提议。
- `intent_matched` 保留为兼容字段，语义固定为 `intent == "provide"`（`asr_postprocess.py:482` 即 `intent_matched = intent == "provide"`）。
- **向后兼容依据**（2026-09-16 修正，原论断有误）：旧客户端 `HybridAPI.gd` 的白名单是 `[provide, delegate, off_topic]`，不在其中时回退到 `intent_matched`。由于 `intent_matched` 恒等于 `intent == "provide"`，**`accept` 与 `reject` 都退化为 `off_topic`**（原稿称 `accept` 会退化成 `provide`，与上述等式矛盾，已作废）。
  - 后果可接受：PROPOSED 态下旧客户端把 `accept` 走成"没听懂"分支（`_handle_proposal_not_understood` → 重问一次），既不崩、也不会写错槽位值；`reject` 则与既有 `_is_decline_utterance` 文本兜底同向（重问/换一个）。
  - 因此 `accept`/`reject` 的**实际收益只对升级后的客户端生效**，且升级项已落地（`HybridAPI.ASR_INTENT_VALUES` 五值 + `_classify_proposal_reaction` 判定表）。
- **`extracted` 在非 provide 时被清空**（`asr_postprocess.py:480`：`extracted = {} if intent != "provide" else ...`）。所以提议态的接受判定**不得**依赖 `extracted[key] == proposed_value` 回填，必须认 `intent == "accept"`。
- 在 `reject` 落地前，含名字的否定句一律 `off_topic`（`rule_007`）；扩标签时是**细化**该裁定，不是推翻。

### 3. 新增判据字段（每个判决都要能说清"凭什么"）

| 字段 | 类型 | 语义 | 落地状态 |
|---|---|---|---|
| `verdict_source` | `"rule"` \| `"llm"` \| `null` | 判决来源；降级（`applied=false`）时为 `null` —— **降级不是判决** | **已落地**（2026-09-16） |
| `matched_rule` / `matched_candidate` | str \| null | 规则层命中的规则名与候选值（可复核：能在玩家话语里指出那一段） | **已落地**，且 `matched_rule` 已有真实消费者（客户端 `_is_retraction_downgrade`） |
| `shortcut_hit` | bool | 是否走本地短路、未调 LLM | **暂不落地**，见下 |
| `shortcut_confidence` | float \| null | 本地匹配置信度。**与既有 `confidence` 分离**，后者实际是 Whisper 的 `language_probability`，两者混用是既有缺陷 | **暂不落地**，见下 |

**为什么 `shortcut_hit` / `shortcut_confidence` 暂不落地**：本次实现里**没有 LLM 之前的短路路径**——规则层跑在模型之后，每次请求都已经调过 LLM。`RuleOutcome.shortcut_hit` 在规则层内部的含义是"取值由规则层给出"，与契约里的"未调 LLM"**不是一回事**；把前者填进后者就是发一个假判据。将来真做本地短路时再加，并同时明确两处语义。

**`verdict_source` 的一处口径**：规则层弃权（确认不了命中）时，取值被清空但意图仍由模型承担，故记 `"llm"`；规则层采纳了模型给出的"更紧"自由槽取值时（`rule_013`）也是 `"llm"`，同时用 `matched_rule="free_slot_model_value_tighter"` 记下"采纳由本层做出"。即：`verdict_source` 说**判决归谁**，`matched_rule` 说**哪条规则起了作用**，两者不互为充要条件。

### 4. 规则层实现顺序

| 步骤 | 谁做 | 依据 |
|---|---|---|
| 1. 意图判定（provide / delegate / off_topic …） | **模型** | `rule_003` |
| 1b. 合法性归一：两处**只能降级为 `off_topic`** 的修正 | 规则层 | `rule_005`/`rule_010`（见 §1 例外） |
| 2. 去壳：丢弃候选**之外**的内容（前置引导词、后置附带内容） | 规则层 | `rule_006`/`rule_008`/`rule_009` |
| 3. 召回边界：候选**之内**只纠识别误差，不纠学习错误 | 规则层 | `rule_004`/`rule_009` |
| 4. 多候选仲裁 → 唯一候选 | 规则层 | `rule_002` |
| 5. 自由槽例外：保留玩家说出的值，禁止改写成值池成员 | 规则层 | `rule_001`/`rule_007` |
| 6. `delegate` 门控：槽位声明 `delegatable` 才成立 | 规则层 | `rule_005` |
| 7. 判据落字段、扩 `accept`/`reject` | 契约 | 本 ADR |

### 5. 去壳 vs 召回边界：候选之外 vs 候选之内

这是一条分界，不是一个阈值：

- **候选之外**（引导词『Say』『Repeat after me』、后置附带内容、自由槽的『我叫/我是』壳）→ **按去壳丢弃**，不算"多词"。实测的模型行为**不对称**：它丢前置引导词，不丢后置附带内容 → 规则层必须**两个方向都处理**。
- **候选之内**（『Nice meet you』漏 `to`、『Meet you nice』乱序）→ **学习错误，禁止纠正**，落情形 2（保留 `provide`、清空 `extracted`）。
- 判据：**候选句本身是否完整、可复核地对齐**。
- **取值的落地细节（硬约束）**：`extracted` 必须是裸值。客户端的 `_extract_name`（`BeginningFPController.gd:767-776`）只剥五个固定前缀（`my name is`/`i am`/`i'm`/`我是`/`我叫`），**没有『叫我』**；若返回整句，剥壳后剩下的内容会经 `player_display_name` → `GameManager.set_player_info` → `save_progress()` **持久化成玩家名字**，并被 NPC 台词模板与 ASR 上下文的 `user_id` 使用。自由槽的值会落盘，所以"这一层不能出错"不是风格问题。

### 6. 多候选仲裁（`rule_002`，五级全函数）

次序（实现期依实测细化，见 `rule_002.refinements`）：

1. **子串关系取最长** —— 玩家说了更完整的表述就记更完整的。
2. **问句中被引号标出的目标** —— 『请对腓腓说『出发』』里的 `出发`。
3. **问句中包含的候选** —— 无引号时退到包含关系。
4. **首次出现位置** —— 互不包含且问句无线索时，按玩家先说的那个。
5. **候选表顺序** —— 仅对完全相同的候选才可能触发。

`extracted[key]` 必须**恰好等于某个候选**：禁止拼接、禁止整句。

为什么要这三条细化（每条都由一个被弄坏的既有用例逼出来）：

| 细化 | 不细化的后果 |
|---|---|
| 子串关系**排在**本轮目标之前 | `cs_018`『Nice to meet you too』被问句里较短的 `Nice to meet you` 截断 |
| 引号目标强于包含关系 | `cs_038`『继续吧，我们出发』问句里 `出发` 与 `继续` 同时出现（『我们就继续旅程』），仅靠包含关系区分不了 |
| **精确命中优先于模糊命中** | `cs_058`『Nice to meet you, my name is Tom』的 5 词窗口 `[nice,to,meet,you,my]` 与候选 `Nice to meet you too` 只差 2 字符（my→too），规则层会**凭空补出玩家没说过的 too** |

### 7. 自由槽例外（`rule_001`）

`person_name` / 无候选表时，`extracted` 保留玩家说出的值（只允许去壳归一），**禁止**改写成值池成员 —— 否则等于把策划池里的名字冒充成孩子自报的名字。值池只用于委托提议；委托的产物是**提议**（`guidance` + 客户端完成器），不是 `extracted`（`rule_005.exception`）。

### 8. `delegate` 的成立条件是槽位声明可委托（`rule_005`）

判据是**槽位属性**，不是句子形态：`delegatable: true`（带值池/提议模板）才判 `delegate`；未声明可委托的槽位（含封闭题）上说「再换一个」「随便选一个」→ `off_topic`。封闭题的 `candidate_answers` 只说明"有值池"，不构成可委托槽位。`delegatable` 与 `value_pool` 已在 context 透传且已出现在 prompt 文本中（`ExpectedSlot` 是 `extra="allow"`），**无需改透传逻辑**。

### 9. 短路三条件与弃权

规则层短路必须**三条件同时成立**：① 匹配分数高于该维度阈值；② 完整命中（**整词边界**，非子串）；③ 命中值来自候选白名单或槽位声明的值池。任一不成立 → **弃权**，交回 LLM 原路径。

**匹配维度的实现现状（2026-09-16 核对，此处原先写成了"已声明的能力"）**：

| 维度 | 状态 |
|---|---|
| 归一化精确 | 已实现 |
| 编辑距离（含**词数守恒**） | 已实现（`rule_004` 校准，阈值 0.20） |
| 整词匹配（token 切分，避免 "Nolan"→"no"） | 已实现 |
| 去壳 / 指令回声 / 语气词 / 附带问句 | 已实现 |
| **拼音 / 近音（仅闭集与名字槽）** | **未实现**——`RuleOptions.phonetic` 只是配置项，模块内没有任何实现，也没有 `pypinyin` 依赖 |

拼音维缺失的**可见后果**（由"决策跑原始 ASR 文本"这条改动暴露）：模型把「暑假」按同音纠成候选「书架」时，规则层在原始文本上确认不了命中 → 弃权清空 `extracted`。行为仍然安全——`corrected_text` 原样透出，客户端 `_asr_answer_text` 回退到它，玩家看到的仍是「书架」，只是这条取值没有规则层背书、客户端按"待确认"处理。边界用例：`test_postprocessor_abstains_on_homophone_it_cannot_verify`。

**为什么这个缺失此前一直不可见**：最初的接线把规则层的**决策**也放在 `corrected_text` 上跑。模型已经替规则层把学习错误纠成正确答案之后，规则层再"确认命中"，于是同音维的缺失被掩盖——**同时也掩盖了 `rule_004` 最怕的那种误判**（`cs_044`「Nice meet you」被确认成「Nice to meet you」）。修法与教训见 §10。

### 10. 实现期补的两条裁定：`rule_012` / `rule_013`（都是**收窄**本层权限）

两条都不是新功能，而是把本层"不该做的事"写清楚。共同点：**发现路径都是"规则层接入生产路径"这一步**——单元测试与离线回放都跑在存量模型输出上，只有把真实调用链接起来才暴露。

| 裁定 | 收窄了什么 | 触发场景 |
|---|---|---|
| `rule_012` | 归一化长度 < 3 的候选**必须精确匹配**（`SHORT_CANDIDATE_LEN = 3`） | `CHAR_EDIT_MIN = 1` 的本意是"避免 3 字候选被 0 容忍卡死"，但对长度 1 的候选，容忍 1 个编辑等于**任何字都算命中**：实测 `find_hits("我觉得是B", ["A"])` 返回 5 个命中。字母识别（A/B/C）是生产上真实的候选形态 |
| `rule_013` | 自由槽里模型给出**更紧**的取值时，本层不得用重算值覆盖它（`_is_tighter_free_value`） | 「我叫小北，你是谁？」模型正确给出「小北」，本层按壳与标点重算得到「小北你是谁」（`_QUESTION_TAIL` 不匹配「你是谁」，两分句被拼接）。**模型能判断"哪一段是名字"，正则不能** |

两条都遵循同一个方向：**本层只该修坏值，不该覆盖好值；只该收窄，不该扩张**。`rule_013` 的条件必须是"更紧"（模型值是重算值的真子串）而非"看起来干净"——模型也可能给出更脏的值（整句、漏去壳），那时重算正是要修它。

**用例集盲区（已补）**：原有 101 例没有任何长度 < 3 的候选，`rule_012` 的问题在单测与回放两轮里都不可见。已补 `cs_068`（单字候选仍能精确命中）、`cs_069`（说了 D、候选 A/B/C → 不得凭空确认）、`cs_070`（`rule_013` 锚点），用例集 101 → 104。

### 11. 规则层的输入是**两个文本**，不能合一

`apply_rules(text=..., corrected_text=...)`：

| 参数 | 用在哪 | 为什么 |
|---|---|---|
| `text`（**原始 ASR 文本**） | 一切**决策**：命中判定、召回边界（`rule_004`）、撤回检测（`rule_010`）、合法性归一 | `corrected_text` 里模型可能已经把孩子的**学习错误**改成了正确答案；在它上面判定等于让模型自己给自己判卷 |
| `corrected_text`（模型纠错文本） | 仅**自由槽取值的表面形式** | 自由槽的值会进存档（`extracted.name` → `GameManager.save_progress()`），ASR 噪声应在表层被模型修掉 |

**代价（实测，不是推演）**：把决策放在 `corrected_text` 上时，`cs_044`「Nice meet you」/`cs_045`「Meet you nice」/`cs_061`「Say Nice meet you」/`cs_043`「Nice to meetchu」四例全部被"确认命中的候选值"，即把孩子的学习错误改写成了满分答案——正是 `rule_004` 立规矩要防的事。改到原始文本后四例全部转绿。

**这个教训的一般形式**：模型与规则层串联时，**规则层必须看到模型的输入，而不只是它的输出**。否则"模型的纠错"会被规则层当成"事实"，两层叠加后反而放大错误。

**回放器的口径**：`scripts/replay_intent_rules.py` 只传 `raw_text`（评测报告不存 `corrected_text`），因此回放验证的正是"决策跑原始文本"这一口径——也就是说，此前回放的 101/101 与生产接线的行为**本来就不一致**，这个不一致在接入当天就以四个用例失败的形式暴露了。

## 考虑过的选项

- **A. 维持现状（规范化写在 prompt 里，不扩契约）** —— 拒。实测已证明它不可靠：同一份 prompt 下 `cs_007` 规范化而 `cs_009` 不规范化；更重要的是**没有判据字段就无法定位错误来源**（§14 的降级污染问题正是靠新增字段才暴露的）。prompt 是概率性的，不能作为口径的承载体。
- **B. 让规则层接管意图判定** —— 拒。`cs_025`「我不想出发」含候选「出发」，规则层凭命中就会把它判成接受（F1）；意图需要语境，规则层读不懂。这也是 `rule_003` 把权限边界写进契约的原因。
- **C. 只扩 `intent` 五值、不加判据字段** —— 拒。少改一点，但失去"每个判决带判据"（P4）；规则层一旦误判将无法复核是哪一层判的。
- **D. 让 voice-service 持跨轮槽位状态以支持 `accept`/`reject`** —— 拒。ADR-0001 已论证：值池与状态机在前端，把"持值池的层"与"持状态的层"劈成两半更碎，且破坏无状态、可水平扩展、双客户端复用。`accept`/`reject` 因此只作为**标签**输出，状态推进仍归客户端。

## 后果

**voice-service 侧**
- 新增规则层模块（建议 `src/services/intent_rules.py`）与新增依赖 `pypinyin`（仅在 `closed_set` 与 `person_name` 启用）。
- `_system_prompt` 需按本契约调整措辞（尤其"仅在槽位声明可委托时才用 delegate"）。
- **无状态边界不变**（ADR-0001），不新增存储。

**客户端侧（Godot；Cocos 后续同步）· 2026-09-16 已实现（工作树，提交顺序待协调）**
> 说明：`BeginningFPController.gd` 此刻含他人未提交的「主人房续行」特性，本节的 `rule_010` 门控插在该特性新增的 `_handle_resume_asr_result` 内，两者在 diff 上属于同一 hunk，无法分别提交；故本节描述的是**已实现并测试通过**的代码，提交时点取决于该特性的落地。
- `HybridAPI.gd` 意图白名单 3 → 5：新增 `ASR_INTENT_VALUES` 常量与 `get_asr_matched_rule()`（读 §3 的 `matched_rule`，`null`/缺失统一归空串）。`get_asr_intent_matched()` 语义不变，仍为 `intent == "provide"`，并在注释中固定"`accept`/`reject` 一律返回 false"这一契约事实。
- `BeginningFPController.gd` 提议态表态收敛为**单一判定表** `_classify_proposal_reaction(intent, text)`（纯函数，便于单测）：`reject` → 拒绝；`accept` → 接受；否则退回 `_is_decline_utterance(text)` 文本兜底（兼容旧 voice-service 与模型漏判）；`provide` + 有内容 → 接受。
- **`rule_010.client_gap` 已闭合，但采用的门控与本节原建议不同**：原建议"给 resume 路径加 intent 门控"存在真实回归风险——模型一旦把合法口令句判成 `off_topic`，玩家会被**卡在主人房**（该路径的失败后果是切不了场景，不可自愈）。因此改为只认**明确判据**：`_is_retraction_downgrade(result)` 比较 `matched_rule == "retraction_after_target"`。
  - 精确性：只有规则层真的做了那一次降级才拦截，模型自身的 `off_topic` 不参与判定。
  - 零回归：规则层未接入时 `matched_rule` 为空 → 门控失效 → 行为与今天完全一致（已由 `test_beginning_fp_intent_contract.gd` 固化）。
  - `matched_rule` 因此从"可复核判据"升级为**有真实消费者的契约字段**（此前 §3 的五个字段均无消费者）。

**待决项**
- `cs_043`（`meetchu`，2 处编辑 / 15.4%）是**阈值校准探针**：当前模型能纠正它，采用 15% 起步阈值会让它从通过变为不通过。纳入（阈值提到 ~20%）或排除都可接受，但必须**显式决定并记录**。
- 真实样本锚点：当前用例全部是 `agent_authored`，分布偏差已声明，20–30 条真实样本仍是 TODO。

**回归与门禁**
- **定义完成**：以下验收目标转绿，且不新增退步。按 2026-09-16 的 N=5 实测，分三类（分类本身是回归的判据，别只看总数）：
  - **确定性失败 9 项**（`applied_pass_rate = 0.00`，规则层必须修好）：`cs_009`（取候选规范值）、`cs_041`（本轮目标优先）、`cs_043`（校准决议：词数变化不纠错）、`cs_044`/`cs_045`/`cs_061`（学习错误被改写）、`cs_047`（封闭题不该出 delegate）、`cs_065`/`cs_066`（迟疑句被当确认）。
  - **不稳定 3 项**（部分通过，需收敛到 1.00）：`cs_040`（0.4，整句 vs 候选翻转）、`cs_058`（0.4，后置附带内容）、`neg_017`（0.8，复读上一轮）。
  - **历史翻转 1 项**（当前 1.00，但翻转过，纳入观察）：`cs_046`（封闭题「再换一个」）。
  → 合计 **13 项**均须转绿；`baseline.json` 的 `note` 记录同一清单。
- 双门禁（最差桶准确率 + 抖动率）+ 降级率门禁；准确率只统计已落地判决（provider 降级不是模型答错）。
- 变更必须带分桶 delta；基线更新按 §14.10 修正规则：**判据是"被测代码变没变"** —— 未变走增量合并，变了先做定标验证。

**风险**
- **规则层假阳性 = 新的 F1**，且比模型的更隐蔽。`Nolan`/`Nora` 被 `no` 误判这个坑项目已踩过一次（`BeginningFPController.gd:536` 注释），故整词边界是硬约束。
- 薄桶不棘轮：桶内落地用例数低于基线 50% 时不参与判定，避免"2 例全对"报假进步。
- 双端契约同步是主要工时风险（Godot + Cocos）。

## 参见

- ADR-0001（意图标签集与"识别在 voice-service、完成在前端"的分工；本 ADR 细化其标签集）
- `docs/plans/2026-09-15-intent-accuracy.md`（度量口径、11 条裁定全文、验收目标与合并规则）
- `services/voice-service/tests/intent_eval/rulings.jsonl`（裁定记录：decision / rationale / exception / calibration_data / client_gap）
- `services/voice-service/tests/intent_eval/README.md`（评测集用法、门禁规则、裁定流程）
