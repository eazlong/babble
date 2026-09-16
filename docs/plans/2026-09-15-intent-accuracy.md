# 目标意图判定准确度：评测尺子 + 确定性规则层

**状态**: proposed
**日期**: 2026-09-15
**范围**: `services/voice-service/src/services/asr_postprocess.py` 的目标意图判定链路（`target_intent` / `intent_description` / `expected_slots` / `candidate_answers` → `intent` / `extracted`）
**方向选定**: A（评测尺子）+ C（确定性规则层前置与契约扩展）
**不在范围**: ADR-0001 的无状态边界本身、值池与槽位状态机（仍归前端）、音频端到端评测、离线深度补评链路

---

## 1. 问题陈述与失败模式

voice-service 当前的"目标识别"是**单次 LLM 一次性出结论**：把上下文 JSON 与规则说明塞进一次 `chat.completions` 调用（`asr_postprocess.py:501-545`），拿回 JSON 后做轻量过滤即返回。链路本身没有确定性校验层，也没有任何准确度度量。

| 编号 | 失败模式 | 机制与证据 |
|---|---|---|
| **F1** | 误接收：跑题/乱说被判 `provide`，垃圾值填死槽位 | 判定完全依赖模型自觉（prompt 里只有 `Do not invent slot values when intent is not matched.` 这类文字约束，`asr_postprocess.py:501-520`）；且 `intent_matched` 由 `intent == "provide"` 机械推导（L287-290） |
| **F2** | 误拒：正确作答被判 `off_topic`，孩子被反复重问 | 闭集题只把 `candidate_answers` 写进 prompt（"prefer candidate_answers"，L514），没有拼音/近音/编辑距离匹配层；中文名与中英混说尤其吃亏 |
| **F3** | 标签混淆：`provide` ↔ `delegate`；PROPOSED 态下"接受提议/拒绝/换一个"三分不开 | 意图标签只有三值（`IntentLabel`，L32）；客户端被迫自建 `DECLINE_MARKERS`（`BeginningFPController.gd:531-545`）与字母/指令本地分类（`WordSpiritLibraryArchiveHallController.gd:14-21`、L243-255） |
| **F4** | 故障静默放行：一切异常都变成 `provide` | `_fallback()` 的容错设计：除 `missing_context` 外一律 `intent=provide`、`intent_matched=True`（L478-496）。网络抖动会导致"孩子答对了"的记录，实为误接收 |
| **F5** | 不稳定：同一句话跨轮判定漂移 | 单次调用、无投票、无自洽性检查；`temperature=0.1` 压不住上下文变化带来的翻转 |

**根因层：不可度量。** `tests/test_asr_postprocess.py` 只断言响应契约与降级路径（三个端点共享的成功/降级契约），没有任何一条断言"这句话该判 `provide` 还是 `off_topic`"。因此 prompt 的任何改动都是盲改，准确度是形容词而非数字。

---

## 2. 已定约束

1. **ADR-0001 无状态边界不变**：voice-service 不造值、不持槽位状态、不解释值池；跨轮上下文靠客户端每轮重传 `recent_turns` 重建。
2. **双客户端契约**：Godot 与 Cocos 复用同一 ASR 响应契约，改动必须向后兼容（依据见 §6）。
3. **成本预算**：允许**最多 2 次** LLM 调用，但本计划一期只使用 1 次（规则层短路实为**减少**调用量）；第二次调用留给后续的独立校验方向。
4. **平台事实**：`requirements.txt` 当前无 `pypinyin`，引入与否见 §6.1。

**证据索引**

| 事实 | 位置 |
|---|---|
| 六道闸门与降级语义 | `services/voice-service/src/services/asr_postprocess.py:113-163, 478-496` |
| LLM 调用参数（json_object / temp 0.1 / length 重试） | 同上 `L367-415` |
| 意图归一与槽位白名单过滤 | 同上 `L287-290, 452-458` |
| guidance 与"已追问过"判定 | 同上 `L460-476` |
| 非对话任务旁路（`task_mode`） | 同上 `L134-140`；`WordSpiritLibraryArchiveHallController.gd:818-824` |
| 置信度实为语种概率 | `whisper.py:136`（`info.language_probability`） |
| 响应契约组装 | `src/api/routes/asr.py:31-67` |
| 引擎优先级链 | `src/services/service_manager.py:63-75, 94-143` |

---

## 3. 支柱与反支柱

### 支柱

**P1 先度量后调参（Measure before tune）**
任何 prompt / 规则 / 模型改动都必须带分桶 delta；"我觉得更准了"不进入代码库。
*Design test*：在"换个更大的模型试试"与"先补 20 条同类失败样本"之间 → **选后者**。
*张力与例外*：线上救火允许跳过，但 48h 内必须补样本，否则该改动**不得进入 baseline**（下次会被当作退步打回）。

**P2 确定性优先，模型兜底（Deterministic first）**
能用本地代码算出的判定（闭集候选匹配、姓名归一、整词边界、拼音/编辑距离）不问 LLM；LLM 只处理规则层明确弃权的样本。
*Design test*：闭集题候选匹配 → **选本地短路**，即使 LLM 也能答对。
*张力*：直接对撞 P3——规则层的假阳性就是新的 F1，且比 LLM 的 F1 更隐蔽。

**P3 保守接收，但追问有上限（Conservative accept, bounded nagging）**
判定层与规则层分歧时不接受；但"追问"全局最多一次（复用既有 `confirmation_already_asked` 机制，`asr_postprocess.py:460-476, 542`）。
*Design test*：分歧时 → 判不通过并追问；**若本轮已追问过** → 放行但打 `low_confidence` 标记、不再追问。宁可放一次可疑答案进下游打分，也不让孩子被问第三次。

**P4 每个判决带判据（Every verdict carries its evidence）**
输出必须带 `verdict_source`（`rule`/`llm`）、`matched_rule` / `matched_candidate`、命中的闸门。没有判据的新标签不予合并。
*Design test*：想加 `chitchat` 标签 → 先回答"它的判据字段与回归样本是什么"；答不上就不加。
*张力*：与 P1 的"最快拿到数字"抢工时——判据字段是成本，收益要到规则层落地才兑现。

### 反支柱

- **A1 不以"换更强的模型"作为主解法** —— 同时打穿成本预算（预算批的是 2 次调用，不是 2 倍单价）与可复现性（换模型 = baseline 全部失效）。
- **A2 不在 voice-service 里造值或持槽位状态** —— ADR-0001 的边界。一旦破了，值池、状态机、双端复用、水平扩展会一起塌。
- **A3 不追求覆盖完整意图空间** —— voice-service 只回答"这个槽位被填了吗、是谁填的"。跑题的语义分类不是它的职责，否则 `intent` 会长成第二个 dialogue-service。
- **A4 不用真实儿童语音做一期手感调参** —— 一期只用文字集；音频集二期再上，混着调会让变量不可分离。

---

## 4. 核心循环（以批次为主）

**30 秒循环（原子动作）**
- 评测侧：`python scripts/run_intent_eval.py --bucket open_slot` → 秒级出混淆矩阵与 baseline delta。
- 规则侧：一条样本进来 → 规则层命中即短路（省一次 LLM、省 1–3 秒），未命中转 LLM 原路径。

> **接口硬约束**：评测 runner 的输出 schema 必须**现在就为规则层预留字段**——`verdict_source`、`shortcut_hit`、`matched_rule`。否则规则层落地时要重造评测器数据结构。

**5 分钟循环（一个批次）**
一个分桶跑完 → 人工过一眼该桶全部失败样本 → 决定"改规则阈值"还是"改 prompt 措辞"。
*裁决规则（必须有牙齿）*：**同一分桶内 ≥3 条同因失败 → 必须转成规则或判据字段，禁止再用 prompt 措辞打补丁。**

**会话循环（一次迭代）**
一个改动 → 全量分桶 → 与 baseline 对比 → **某桶退步 >2pt 则整体拒绝**（棘轮原则）→ baseline 更新作为一次显式 commit（进 diff、进 review）。

**进度循环（长期）**
棘轮基线 + 分桶扩充。**线上每发现一例新失败 → 立刻作为一条样本进对应桶。** "失败即样本"是评测集不脱节的唯一机制。

**团队动机侧（SDT 适配）**
自主性：阈值与 baseline 在仓库里，团队自己调，不依赖外部标注。胜任感：每次改动都有 delta 数字。关联性：样本来自客户端真实传的 context 组合。

---

## 5. 度量口径

### 5.1 双门禁（回归门禁只看这两项）

1. **最差桶准确率（min-bucket accuracy）** —— 防止"总体不错但某一桶坑死"。
2. **抖动率（flip rate）** —— 同一输入重复 N 次，结论翻转的比例。这是 F5 的直接度量。

> **成本硬约束**：抖动率**只在 nightly / slow 通道**跑（N=5），日常批次不跑。否则门禁一次要烧几十次 LLM 调用——不写进文档就会被违反。

总体准确率、成本加权分数一并**记录**在报告中，但**不作为门禁**。

### 5.2 分桶清单

| 桶 | 覆盖内容 | 一期样本量 |
|---|---|---|
| `open_slot` | 开放题（无候选答案、无可委托值池） | 40–60 |
| `closed_set` | `candidate_answers` 非空的封闭题 | 60–80 |
| `person_name` | `expected_answer_type == "player_name"` / `person_name` 槽位，含可委托 | 50–70 |
| `proposed_state` | PROPOSED 态下的接受 / 拒绝 / 换一个三分 | 30–50 |
| `negative` | 负样本：NPC 问题回声、复读上一轮答案、纯语气词、中英混说、ASR 典型误听 | 60–80 |
| `non_dialogue` | `task_mode != "dialogue"` 旁路 | 10–20 |

合计 250–360 条。**每桶至少 3 条来自真实日志或手写**；另置 20–30 条真实样本作锚点。样本由 LLM 生成带来的分布偏差**写进文档，不假装它是真值**。

### 5.3 样本 schema（含为规则层预留字段）

```jsonc
{
  "id": "closed_set_0007",
  "bucket": "closed_set",
  "raw_text": "出发",                     // 一期为文字，不含音频
  "context": {                           // 与客户端实际传参同构
    "npc_question": "...",
    "expected_slots": [{ "key": "answer", "type": "keyword", "description": "..." }],
    "expected_answer_type": "keyword",
    "target_intent": "provide_source_name",
    "intent_description": "...",
    "candidate_answers": ["出发", "Let's go", "继续"],
    "recent_turns": [],
    "task_mode": "dialogue"
  },
  "expect": {
    "intent": "provide",
    "extracted": { "answer": "出发" }
  },
  "provenance": "llm_generated | real_log | handwritten",
  "note": "可选：这条样本要钉住什么"
}
```

**运行期输出（评测报告每例）**

```jsonc
{
  "id": "closed_set_0007",
  "bucket": "closed_set",
  "actual": { "intent": "provide", "extracted": { "answer": "出发" } },
  "pass": true,
  "verdict_source": "rule",      // rule | llm  ← 为规则层预留
  "shortcut_hit": true,          //            ← 为规则层预留
  "matched_rule": "closed_set_exact_zh",
  "latency_ms": 12,
  "llm_called": false
}
```

**报告指标**：总体准确率、各桶准确率（含最差桶）、混淆矩阵（含新增 `accept`/`reject` 的 5×5）、抖动率、短路命中率、短路路径准确率、LLM 调用量与耗时。

---

## 6. 规则层设计

### 6.1 依赖决策

**引入 `pypinyin`。** 理由：一期文字集里中文名匹配是 F2 的主要来源（孩子说"艾灵"，期望值可能是 `Ailing`），自实现声母韵母近似覆盖面吃不住；代价仅镜像 +~5MB。约束：**拼音匹配只在 `closed_set` 与 `person_name` 启用**，且必须同时满足整词边界 + 候选白名单内 + 编辑距离阈值。

### 6.2 匹配维度

| 维度 | 用途 | 约束 |
|---|---|---|
| 精确匹配（归一化后） | 闭集题、候选答案 | 归一化：去空格/标点、大小写、全半角 |
| 拼音 / 近音匹配 | 中文名与中文候选 | 声母韵母近似 + 声调忽略 |
| 编辑距离 | ASR 轻微误听 | 阈值按词长分档，短词严、长词松 |
| 中英混说归一 | `cn_en` 输入 | 语言无关的等价类（如 "出发" ↔ "let's go"） |
| 整词边界 | 英文短标记 | **必须整词匹配**——子串匹配会把 `Nolan`/`Nora` 误判成 `no`（该坑已在 `BeginningFPController.gd:533` 注释中记录） |

### 6.3 短路触发条件（三条件同时成立）

1. **高置信**：匹配分数高于该维度阈值；
2. **整词/完整命中**：不是子串或片段命中；
3. **候选白名单内**：命中值必须来自 `candidate_answers` 或槽位声明的值池。

条件不成立 → **弃权**，交回 LLM 原路径（规则层永不"猜"）。

### 6.4 契约扩展（向后兼容的加法）

`intent` 由 3 值扩至 5 值：`provide` / `delegate` / `off_topic` / **`accept`** / **`reject`**。

**兼容性依据**：`HybridAPI.gd:429-437` 的实现是"`intent` 不在 `[provide, delegate, off_topic]` 白名单内时回退到 `intent_matched`"。因此旧客户端遇到 `accept` 会退化成 `provide`——**恰好是语义最接近的降级**；遇到 `reject`（`intent_matched=False`）退化为 `off_topic`，与客户端现有 `_is_decline_utterance` 兜底行为一致，不崩。

**新增输出字段**：
- `postprocess.verdict_source`: `rule` | `llm`
- `postprocess.matched_rule` / `matched_candidate`
- `postprocess.shortcut_hit`: bool
- `postprocess.shortcut_confidence`: float（与 `confidence` 分离，避免继续混用 `language_probability`）

**客户端配套改动**：`HybridAPI.gd` 的意图白名单扩展；`BeginningFPController.gd` 的 `_is_decline_utterance` 改为优先读 `reject`，但**保留兜底**以防旧 voice-service 版本。

> 契约扩五值改的是 ADR-0001 定下的标签集，实施时**另立 ADR**（拟 `docs/adr/0009-*`），不并入本计划文档。

### 6.5 delegate 不做规则化

`delegate` 的判定**不从 LLM 手里拿走**——委托表达是开放集（"你帮我起一个吧" / "随便选一个" / "你想一个"），规则层盖不住，硬盖就是制造新的 F1。

---

## 7. MVP 定义与验收判据

**MVP** = runner + 2 个桶（`negative`、`closed_set`）+ baseline 文件 + pytest 门禁（`@pytest.mark.intent_eval`）。

**验收判据（唯一一条）**：面对一次 prompt 改动，它能说出"**最差桶是哪个、退步多少**"。

做到了，说明这把尺子能用；做不到，后面所有工作都不必开始。

---

## 8. 风险与缓解

| 类别 | 风险 | 缓解 |
|---|---|---|
| 技术 | golden set 由 LLM 生成 → 分布偏差 | 每桶 ≥3 条真实/手写样本；20–30 条真实样本锚点；偏差写入文档 |
| 设计 | 抖动率需重复 N 次 → 成本 ×N | 抖动率只在 nightly / slow 通道跑（N=5），日常批次不跑 |
| 工程 | 规则层假阳性 = 新 F1，且旧客户端会当 `provide` 接受 | 短路三条件同时成立才触发；返回 `verdict_source` 供线上回溯 |
| 流程 | 评测集三个月后与实际输入分布脱节 | "失败即样本"：线上每例新失败立刻进桶 |
| 流程 | 门禁退步被"顺手更新 baseline"绕过 | baseline 更新必须是显式 commit，进 diff 与 review |

---

## 9. 范围分层与时间

**全量愿景**：5 桶文字集 + 规则层（闭集 + 名字）+ 契约扩 5 值 + 判据字段 + 双门禁进 CI。

**砍一半**：3 桶（少 `proposed_state` / `open_slot`）+ 规则层只做闭集 + 契约只加 `reject`/`accept`，不加判据字段。

**最小可交付**：runner + baseline + 门禁（**不含规则层**）。这是唯一"砍了也不亏"的部分——它是规则层的前置，而规则层砍掉后它依然独立成立。

**时间（批次日节奏）**：MVP 0.5–1 天 → 规则层 2–3 天（含约 1 天标注与阈值校准）→ 契约双端同步 1–1.5 天。合计 **4–5.5 天**。

---

## 10. 不做什么

1. **不换更强的模型当主解法**（A1）。
2. **不在 voice-service 造值或持槽位状态**（A2 / ADR-0001）。
3. **不扩到完整意图空间**：不加 `chitchat` / `question` / `letter_name` / `command` 标签（A3）。字母与指令分类继续留在客户端本地（该分工已有 `WordSpiritLibraryArchiveHallController.gd:14-21` 的偏离说明背书）。
4. **一期不引入音频**：不做端到端音频评测，不碰离线深度补评的重跑 ASR 链路（A4）。
5. **不用 `confidence` 冒充字级置信度**：新增 `shortcut_confidence` 与既有 `confidence` 分离；`language_probability` 的错位问题记录在案，一期不做重构。

---

## 11. 实施记录（2026-09-15，方向 A 的 MVP 已落地）

### 11.1 交付物

| 文件 | 作用 |
|---|---|
| `services/voice-service/tests/intent_eval/contexts.json` | 4 个场景上下文模板，形状从客户端真实构造点重建（各自标了 `_source`） |
| `services/voice-service/tests/intent_eval/cases.jsonl` | 70 条可判分用例：`closed_set` 36 + `negative` 34 |
| `services/voice-service/tests/intent_eval/cases_pending_ruling.jsonl` | 待裁定用例（不计入门禁；随裁定推进增减，见 §13） |
| `services/voice-service/tests/intent_eval/harness.py` | 装载 / 判分 / 指标 / 门禁（runner 与 pytest 共用） |
| `services/voice-service/scripts/run_intent_eval.py` | CLI：报告、双门禁、预算闸门、基线棘轮 |
| `services/voice-service/tests/test_intent_eval_gate.py` | 22 条离线测试（含 live 用例 opt-in） |
| `services/voice-service/tests/intent_eval/baseline.json` | live 基线（首次由 `--update-baseline` 生成） |
| `services/voice-service/tests/intent_eval/README.md` | 使用方式、门禁规则、样本约定与**偏差声明** |

**MVP 验收判据已满足**：runner 能说出"最差桶是哪个、退步多少"（报告里 `最差桶 = …` 一行 + 每桶 `与基线` 列）。

### 11.2 首次测量结果（模型 `qwen3.8-27b-fp8`）

| 运行 | 规模 | 总耗时 | closed_set | negative | 总体 | 抖动率 |
|---|---|---|---|---|---|---|
| Run 1（N=1） | 70 次调用 | 46.4s（最慢单次 7.3s） | 0.972 (35/36) | 0.971 (33/34) | **0.971** | 未测 |
| Run 2（N=5，写入基线） | 350 次调用 | 360.6s（最慢单次 37.8s） | 0.972 | 0.988 | **0.980** | **0.0143**（1 例翻转） |

预算实耗：**420 次调用**，全部使用 `--max-calls` 闸门约束。

**两个失败样本，恰好指向两个不同的靶子：**

- **`cs_009`「接着走」→ `extracted = "接着走"`，期望规范化到候选「接着」。五次全错（确定性失败）。**
  同一个 prompt 下 `cs_007`「我们启程吧」却被正确规范化到「启程」。所以问题不是"模型不会规范化"，而是**规范化行为不一致**——这正是方向 C 的规则层最直接的靶子：确定性 canonicalization 一次消掉整类不确定性，且不花钱。
- **`neg_017`「我看到了糖葫芦」→ 判 `provide` 并回填 `糖葫芦`，期望 `off_topic`（F1 误接收）。**
  上下文是 `recent_turns` 里已记录玩家上一轮答过同一句、而 NPC 已换了新问题。它同时也是**唯一抖动用例**：5 次里 3 次对、2 次错（40% 翻转）。这说明难点集中在**需要 `recent_turns` 推理的上下文相关判定**，而不在"识别语气词/复读"这类表层负样本。

**结论（对下一批样本的指导）**：当前 97–98% 的数字**不可当作乐观信号**——这批用例由 agent 依上下文形状编写，负样本以表层跑题为主，偏易。下一步扩桶应优先 `proposed_state` 与 `person_name`（都是上下文相关），并把"复读上一轮"扩成 6–8 条独立小类。

### 11.3 新发现的失败模式（计划文档原 §1 未覆盖）

**F6：provider 返回非 completion 对象 → 未捕获异常 → HTTP 500。**
根因是本仓库 `.env` 里 `ASR_POSTPROCESS_BASE_URL` 缺 `/v1` 后缀：请求打到网关站点首页并拿到 HTML（HTTP 200），OpenAI SDK 于是返回 `str`，`_complete_json` 的 `completion.choices[0]` 抛 `AttributeError`。该异常**不在** `process()` 的捕获列表（`APITimeoutError` / `APIStatusError` / `APIError` / `RuntimeError`）内，直接冒泡到路由 → 500。对儿童玩家的表现是"语音识别失败"，而不是既有的容错降级。

- 影响：任何 provider 形状漂移（网关换首页、代理返回 HTML、上游 502 页面）都会复现，不只是配置写错。
- **已处置（2026-09-15，用户裁定后实施）**：
  1. `.env` 的 `ASR_POSTPROCESS_BASE_URL` 补上 `/v1`（`services/voice-service/.env`，仅此一处值变更）。
  2. `_complete_json` 取 `choices` 前加守卫：
     `if not hasattr(completion, "choices"): raise RuntimeError("provider returned non-completion response: ...")`
     —— 复用既有的 `except RuntimeError` 分支，降级为 `provider_error`（容错放行）。
  3. 回归测试：`tests/test_asr_postprocess_provider_shape.py`（8 条），覆盖 str/bytes/list 三种非 completion 形状、
     降级语义（`intent_matched=True`、原样透传文本）、以及"有 `choices` 但为空"不被误伤的两个分支
     （`player_name` 上下文走本地恢复 `confidence=0.75`；其他类型才落 `provider_error`）。
- **端到端验证**：把 `ASR_POSTPROCESS_BASE_URL` 故意改回缺 `/v1` 的坏值跑评测，结果由"500"变为
  `fallback 2 / 降级原因：provider_error`、`LLM 调用下界 0`——守卫在真实缺陷上生效，不再冒泡。
- 这是本计划中**唯一一处生产代码改动**（MVP 的"零生产改动"约束在此处经用户显式裁定后放开）。
- 附带缺口：`.env.example` 从未记录 `ASR_POSTPROCESS_*` 这套配置（已补，并写明 `/v1` 要求与症状）。

**F7：无连接复用，且实测延迟可超过配置超时。**
`ASRPostprocessor` 是模块级单例但 `client=None`，于是每次 `_call_llm` 都新建并关闭一个 `AsyncOpenAI`（`asr_postprocess.py:338-343, 394-396`）。Run 2 实测**单次最慢 37.8s**，超过 `ASR_POSTPROCESS_TIMEOUT_MS=30000` 的配置值——httpx 的超时是分阶段读超时，不是总时长上限。孩子在对话里等 37 秒不可接受，也会让客户端超时逻辑误判。

- **已处置（2026-09-15，用户裁定 [A] 后实施）**：
  1. `_resolve_client()` 按 `(api_key, base_url, timeout_ms)` **复用**同一个客户端（连接池）。该方法全是同步操作（无 await），在事件循环里天然原子，因此不需要加锁；配置变化时旧客户端进入 `_retired_clients`。
  2. 新增 `aclose()`，并在 `src/main.py` 的 `shutdown` 事件里关闭——注入的客户端不缓存也不关闭（调用方持有生命周期）。
  3. `timeout_ms` 升级为**总时长预算**：`process()` 用 `asyncio.wait_for` 兜住 `_call_llm` 整体（含 `finish_reason=length` 的重试），新增 `except asyncio.TimeoutError` → 既有 `timeout` 降级。httpx 的分阶段超时保留为单请求护栏。
  4. 回归测试：`tests/test_asr_postprocess_client_lifecycle.py`（7 条）——复用、并发只建一个、配置变化才换、`aclose` 释放、注入不被关闭、200ms 预算切掉挂死请求、快请求不受影响。
- **诚实记录：性能收益未被数据支持。** 改动前后各跑一次 live N=1 全量（70 例）：

  | | 总耗时 | 最慢单次 |
  |---|---|---|
  | 改动前 | 46.4s | 7.32s |
  | 改动后 | **51.5s** | 6.90s |

  总耗时反而略高，两次都在同量级波动内。**结论：Run 2 那个 37.8s 的离群值应归因于 provider 侧排队/抖动，而不是建连开销**——"每次新建客户端"是确凿的架构缺陷（无连接池、每请求多一次 TLS 握手与关闭），但把它当作尾部延迟的主因**没有得到证据支持**。
  真正兜住尾部的是第 3 条预算护栏（单测里 200ms 预算确实在 200ms 切断了 30s 的慢响应），而不是连接复用。准确率侧无回归：negative −1.8pt（阈值内）、closed_set ±0.0pt，门禁通过。

### 11.4 相对本计划 §5.3 的 schema 扩展

实测后确定的三处扩展（原设计保留可见，不追改原文）：

1. 用例支持 `context_ref` + `context_patch`（引用 `contexts.json` 模板并打补丁），避免 70 条用例重复粘贴整块 context。
2. `provenance` 枚举定为 `agent_authored` / `human_handwritten` / `real_log`。**当前 70 条全部是 `agent_authored`**，§5.2 要求的"20–30 条真实样本锚点"仍是 TODO，且已写入 README 的偏差声明。
3. 抖动率抽样新增 `--sample-per-bucket N`（每桶等距抽，确定性）。用例文件按桶排块，取前 N 会只覆盖一个桶——这一点已由离线测试钉住。

另外两条实现口径：

- `verdict_source` 的语义定为 `rule` / `llm`，**降级路径不是判决**（`applied=False` 时为 `None`），规则层上线前恒为 `llm`、`shortcut_hit` 恒为 `False`。
- 费用记账按**次**而非按**例**（N=5 的一次全量是 350 次调用，不是 70 次）。

### 11.5 下一步（顺序即优先级）

1. **裁定 9 条待裁定用例**（`cases_pending_ruling.jsonl`），其中 `pr_009` 直接决定 `cs_009` 的期望值是否翻转。
   **进行中（2026-09-15）**：已裁定 `rule_001`–`rule_005`（对应 `pr_009`/`pr_010`/`pr_011`/`pr_001`/`pr_006`，见 §13）；
   待裁定剩 **6 条**：`pr_002`/`pr_003`/`pr_004`/`pr_005`/`pr_007`/`pr_008`。裁定会自然浮出下游问题（`pr_010`/`pr_011` 都是这样来的）。
2. **补 20–30 条真实样本锚点**（真实日志或人工记录），把分布偏差从"声明"变成"缩小"。
3. **扩桶**：优先 `proposed_state`（PROPOSED 态接受/拒绝/换一个）与 `person_name`，并把"复读上一轮"扩成独立小类。
4. ~~**裁定 F6 是否纳入**：一行守卫 + 一条"stub 返回 str"的单元测试。~~
   **已完成（2026-09-15，用户裁定 [A]）**：`.env` 补 `/v1` + `_complete_json` 守卫 + 8 条回归测试，并已用坏 URL 端到端复现验证。见 §11.3。
5. ~~**裁定 F7 是否纳入**：共享 client / 连接复用 / 总时长上限。~~
   **已完成（2026-09-15，用户裁定 [A]）**：见 §11.3 F7，含"性能收益未被数据支持"的诚实记录。
6. **nightly 接线**：基线现已含 `flip_rate`（0.0143），双门禁可以正式启用（N=5 全量）。
   **已完成（2026-09-15）**：见 §11.6。
7. 以上完成后才进入**方向 C**（规则层 + 契约扩五值）。

---

## 12. 评测的接线现状（2026-09-15）

### 12.1 已接线

| 场景 | 入口 | 说明 |
|---|---|---|
| 本地 / PR 离线门禁 | `python -m pytest`（`testpaths = tests`） | 37 条评测相关测试，零成本、不联网、秒级 |
| PR CI | `.github/workflows/ci.yml` → job `voice-service-intent-eval` | 用 `requirements-eval.txt`（**不含** ASR/TTS 引擎）装最小依赖集跑上述离线门禁 |
| nightly 真实评测 | `.github/workflows/intent-eval-nightly.yml`（UTC 18:00 = 北京 02:00）<br>本地等价：`bash scripts/run_nightly_intent_eval.sh` | N=5 全量 + 双门禁 + 费用闸门；产出 JSON 报告 artifact，并打印与上次的趋势对比 |

- nightly 需要的 secrets：`ASR_POSTPROCESS_BASE_URL`（**必须带 `/v1`**）、`ASR_POSTPROCESS_API_KEY`、`ASR_POSTPROCESS_MODEL`。缺任一则只发 warning 并跳过，不会把 nightly 变红。
- 报告落在 `tests/intent_eval/reports/`（已加入 `.gitignore`）；评测集与基线本身仍入库。
- 手工触发：`workflow_dispatch`；省预算：`INTENT_EVAL_REPEATS=1 INTENT_EVAL_MAX_CALLS=80 bash scripts/run_nightly_intent_eval.sh`；零成本验管线：`INTENT_EVAL_STUB=perfect ...`。

### 12.2 顺带修掉的两个接线缺口

1. **`ci.yml` 里 `services/voice-service` 那个矩阵项对 Python 测试不生效**：该目录没有 `package.json`，且全仓库 `package.json` 中没有任何一处调用 `pytest`（已核实）。新增的 `voice-service-intent-eval` job 是目前唯一真正跑 voice-service 测试的 CI 步骤。
2. **`pytest.ini` 未限定 `testpaths`**：默认会收集 `scripts/test_xfyun.py`（手动集成脚本：真加载 Whisper 模型、需要讯飞凭据），它在干净环境下必然失败（`WHISPER_CACHE=/models` 不可写）。加 `testpaths = tests` 后本地套件由 `1 failed / 129 passed` 变为 **`126 passed / 3 skipped / 0 failed`**；该脚本仍可显式运行。

### 12.3 仍未接线（下一批）

- voice-service 的**完整** Python 套件（`tests/test_voice.py`、`test_xfyun_services.py`、端到端路由测试等）需要 `faster-whisper` / `ctranslate2` 等重依赖，CI 尚未覆盖——这是 voice-service 目前最大的质量缺口。
- 建议顺带把 `scripts/test_xfyun.py` 的 4 个用例标记为 `@pytest.mark.integration`（它们本就是手工集成脚本），这样"脚本 vs 测试"的边界由标记而非目录来保证。

---

## 13. 裁定记录

裁定是"这批用例为什么这么期望"的书面依据，逐条落在 `services/voice-service/tests/intent_eval/rulings.jsonl`；契约层面的固化在 ADR（各条的 `folds_into`）。流程与约束见同目录 README。

> **契约已固化（2026-09-16）**：`docs/adr/0009-intent-value-contract-and-rule-layer-boundary.md` —— 11 条裁定的契约化落地（intent 扩五值、判据字段、规则层实现顺序与权限边界、完成判据 = 12 项验收目标转绿）。各裁定 `folds_into` 里的 `docs/adr/0009-*` 即指该文件。

### rule_001（原 `pr_009`，2026-09-15）：封闭题取候选规范值，自由槽不得改写

**裁定**
- 有 `candidate_answers` 的封闭题：`extracted[key]` 回填**命中的候选规范值**（阈值内 top-1）；未达阈值判 `off_topic`，不猜。
- 自由槽（`expected_answer_type=person_name` 或无候选表）：`extracted` **保留玩家说出的值**，只允许去壳归一（去掉"我叫/我是"），**禁止**改写成值池成员。
- `corrected_text` 保留玩家实际说出的话（纠错后），供结构化过程回放与诊断；`extracted` 承载机器可读值，供判定/跨轮上下文/聚合。

**依据（取证过程）**
1. **判定侧零风险**：客户端 `LessonResponseMatcher._matches_any_phrase`（`apps/godot-client/assets/scripts/core/lesson_response_matcher.gd`）用的是 `text.contains(phrase)` —— **containment 而非相等**。玩家原话是候选值的超集，因此规范值与原话**都能通过判定**，取规范值不会降低通过率。
2. **`extracted` 会回流成上下文**：`ChangAnMarketController._accept_current_voice_step()` 把该值写入 `voice_failure_intervention.add_turn("player", text)`，于是它成为下一轮请求的 `recent_turns` —— 直接喂给"复读上一轮"这类判定（即 `neg_017` 的题型），也影响 token 成本。规范值更短更稳定。
3. **可稳定分组**：报告与掌握度聚合按值分组，玩家多说几个字不该产生另一个字符串。
4. **已知行为不一致**：首次 live 测量中 `cs_007`「我们启程吧」被规范化为「启程」，`cs_009`「接着走」没有 —— 同一份 prompt 下口径不统一，只有确定性规则层能保证一致（方向 C 的靶子）。
5. **自由槽例外是硬约束**：`extracted.name` 在 `BeginningFPController.gd:483-508` 会**直接成为玩家名字**，把它替换成策划池里的名字属于内容越权 + 儿童数据失真。值池只用于委托（delegate）提议。

**推论**
- `cs_009` 的期望值「接着」**保留不变**，它是方向 C 必须修好的验收靶子，而不是"期望写错了"。
- 该裁定已变成可执行不变量：`tests/test_intent_eval_gate.py::test_closed_set_expectations_are_canonical_candidates`（封闭题期望值必须在候选表内）与 `test_free_slot_exception_is_documented_where_it_matters`（涉及值池的裁定必须写明例外）。
- **下游新问题 `pr_010`**：一句话命中多个候选值（如"出发，继续"）时如何仲裁？`rule_001` 只裁定了"取候选规范值"，没裁定多命中的选择规则——不裁定它，方向 C 的规则层无法确定性实现 canonicalization。这是裁定过程自然浮出的下一个问题，已进待裁定集。

### rule_002（原 `pr_010`，2026-09-15）：多候选命中的仲裁

**先取证，再裁定。** 写规则之前跑了 5 例 live 探针（`出发，继续` / `Nice to meet you too` / `let's go, next lesson` / `继续吧，我们出发` / `My name is Lily, nice to meet you`），其中 2 例遇网关 500 后重跑。观测到两件事：

1. `出发，继续` → `出发`；`继续吧，我们出发` → **也是** `出发`。两个候选集合相同、出现顺序相反却给出同一结果 —— 说明模型不是按出现顺序选，而是在**跟随问句**（该轮问句是"请对腓腓说『出发』"）。
2. `My name is Lily, nice to meet you` → 返回**整句原话**（`My name is Lily, nice to meet you`），而不是任何一个候选值。

> **勘误（2026-09-15，同日自查）**：这一条最初的记录写成"返回拼接值 `mynameislilynicetomeetyou`，既不是候选也不是原话片段"。原始返回值其实是**带空格标点的整句原话**；`mynameislilynicetomeetyou` 是 `grade()` 打印失败原因时对值做 `normalize_text()`（去空白与标点）后的**比较形式**，被误读成了模型原始输出。差别很关键：整句仍包含候选短语，客户端 containment 判定**照样通过**，所以不存在"误拒"风险——真正的缺陷是**记录里存了整句而不是规范值**（违反 rule_001）。仲裁规则本身不变，但"取不到候选怎么办"的答案因此不同，见 `rule_003`。

**裁定**：仲裁只在**意图已判定为 `provide`** 之后进行（故「我不想出发」这类否定句仍归 `off_topic`，与 `cs_025` 一致）。命中多个候选时按四级优先取第一个满足者：

1. **本轮目标优先** —— 命中集合中有候选出现在 `npc_question`（归一化后）里，取之；
2. **最长匹配** —— 归一化字符数最多者（子串关系时取更具体的长者）；
3. **首次出现位置** —— 句中先出现者；
4. **候选表顺序** —— 表序即策划优先级（客户端把 `clear_phrases` 拼在 `acceptable_phrases` 之前，`ChangAnMarketController.gd:309`）。

`extracted[key]` **必须恰好等于某个候选**：禁止拼接、禁止整句或片段。

**为什么第 3/4 级是反过来排的（改判记录）**：初版把"候选表顺序"排在第 3 级。74 例全量测量中 `cs_040`（两候选等长、问句被改成中性使第 1 级不触发）模型返回了**先出现的那个**（`My name is Lily`），不是表序在前的 `Nice to meet you`。复核后改判，理由是规则质量而非迁就模型：

- 表序优先级依赖"客户端把两个列表拼起来"这一**实现细节**，是脆弱耦合；
- "先说的那个"只依赖玩家自己的句子，与语言、客户端实现都无关；
- `clear > acceptable` 的优先级本来已由客户端判定器单独表达（先查 clear 再查 acceptable），仲裁无需重复编码。

改序后表序退化为只有"完全相同的候选"才可能触发的最终 tiebreak，四级规则是**全函数**：只要 ≥1 候选命中就必然产出唯一值。

**已知局限**：第 1 级依赖 `npc_question` 文本。问句被改写、本地化或只描述任务而不含候选词时（英文候选配中文问句），第 1 级不触发，自动落到第 2–4 级 —— 仍有解，只是退化为"最长/首次出现"。

**落地**：新增 4 条可判分用例 `cs_037`–`cs_040` 分别钉住第 1、1、2、3 级；`pr_010` 移出待裁定集。**下游新问题 `pr_011`**：模型返回非候选值（实测为**整句原话**）时 post-processor 该丢弃 extracted、就地改写、还是判 `off_topic`？rule_001/rule_002 只规定了"应该取候选"，没规定"取不到时怎么办"——方向 C 落地前必须有人回答。该问题已由 `rule_003` 裁定。

### rule_003（原 `pr_011`，2026-09-15）：规则层只收窄取值，不覆盖意图

**核心边界**：规则层是**取值规范化器**，不是意图裁判。按 (模型 intent × 规则层能否在 `corrected_text` 中确认候选命中) 三分：

| 模型 intent | 规则层能否确认命中 | 结果 |
|---|---|---|
| `provide` | 能 | `extracted[key]` = 规则层按 rule_002 仲裁出的候选值（**覆盖**模型给的值，含整句原话）；标 `verdict_source="rule"`；intent 保持 `provide` |
| `provide` | 不能 | **保留 `provide`**，`extracted` 清空为 `{}`（丢弃不可信的值）；客户端 `_asr_text`/`_asr_answer_text` 自动退回 `corrected_text` 判定；标 `verdict_source="llm"`；**不得**改判 `off_topic` |
| `off_topic` / `delegate` | —（不介入） | 保持模型判定，`extracted` 保持空。**禁止**规则层凭"句中出现候选"把 `off_topic` 翻成 `provide` |

模型完全没给 `extracted` 时与"给了非候选值"同表处理。

**依据**

1. **不得改判 `off_topic`（情形 2）**：实测模型在 `My name is Lily, nice to meet you` 上返回整句原话，该值归一化后仍包含候选短语，客户端 containment 判定**照样通过** —— 说明孩子确实答对了。此时判跑题是最坏的 F2 误拒，而规则层并没有"否决模型意图"的权限。
2. **不得凭命中翻成 `provide`（情形 3）**：`cs_025`「我不想出发」句中含有候选「出发」。若规则层凭"出现候选即 provide"，否定句就会被误判成接受 —— 这正是 F1。意图判定必须留给能读语境的模型。
3. **能确认命中时必须改写而不是丢弃（情形 1）**：这是 rule_001 的落地形式。丢弃等于放弃规范值收益（`recent_turns` 变长、聚合分组不稳），而规则层的确认是**可复核的**（它能在孩子的话语里指出那个候选），因此不构成伪造证据。改写时 `verdict_source` 标 `rule` —— 正是该预留字段的用途。
4. **与 `pr_001` 的依赖**：规则层"确认命中"的宽容度（近音/编辑距离召回边界）决定情形 1 与情形 2 的分界。`pr_001` 未裁定前，实现应取**保守匹配**（精确 + 归一化 + 明确的近音表）：宁可落到情形 2（清空 extracted、退回原话），也不要伪造命中。
5. **为什么排除"判 `off_topic`"这个选项**：见第 1 条 —— 孩子答对了，判跑题即误拒。

**验收靶子**：`cs_041`（同句不同问句，模型当前返回整句或错误候选）与 `cs_040`（值形态在"整句/候选"之间翻转，N=5 测量中它是**唯一**翻转用例）。两条都只能靠规则层按 rule_003 收窄取值来修。

### rule_004（原 `pr_001`，2026-09-15）：候选表纠错的召回边界 —— 纠识别误差，不纠学习错误

**原则**：voice-service 可以纠正**识别误差**（ASR 听错、拼读、错字），**不得**纠正**学习错误**（漏词、语序、否定、反义）。

| | 归谁 | 处置 |
|---|---|---|
| 识别误差：`meat`→`meet`、`meetchu`→`meet you` | 不是孩子的表现 | **纠正为候选值**（provide + 候选） |
| 学习错误：`Nice meet you`（漏 to）、`Meet you nice`（语序） | 是孩子的表现 | **不得**改写；按 rule_003 情形 2 清空 `extracted`、退回 `corrected_text` |

**可执行边界**：允许——同词数、逐词对齐，差异仅在字符/音素层面，且整体归一化编辑距离 ≤ `max(1, 15%×候选长度)`（起步值，由方向 C 校准）。禁止——词数变化、词序变化、否定与反义、跨语义替换。**禁止纠错 ≠ 判 `off_topic`**（rule_003 情形 2）。

**依据**

1. **探针实测召回无上下界**：4 条阶梯（`Nice to eat you` / `Nice to meetchu` / `Nice meet you` / `Meet you nice`）**全部**被纠正成 `Nice to meet you`。前两条是识别误差，后两条是学习错误。
2. **代价不对称**：纠正识别误差是还原真相；改写学习错误是**篡改证据**。因为 `extracted` 优先于 `corrected_text`，客户端连错误都看不到——教学纠错与掌握度统计同时失效，也违背 CONTEXT.md「结构化过程回放要还原玩家过程」。
3. **不纠错不会把孩子判成"没作答"**：客户端本就用三档 tier 表达部分正确（真实配置里 `name_register` 只要出现 `name` 即 acceptable 档，`required_keywords` 机制）。`Nice meet you` 会走 understandable/needs_help，而不是 off_topic。
4. **为什么必须有确定性阈值**：同一份 prompt 下模型既纠正 1 处编辑、也纠正语序错乱，说明它的召回会漂移；而 `extracted` 会进记录与聚合，边界必须由规则层执行、可复核、可回归。

**锚点用例**：`cs_019`/`cs_042`（1 处编辑，必须纠错）、`cs_044`（漏词）/`cs_045`（语序）（必须不纠错）、`cs_043`（`meetchu`，2 处编辑 / 13 字符 = 15.4%，**故意留在阈值之外的校准探针**——纳入还是排除由方向 C 显式决定）。

**关系**：`rule_003` 明确依赖本裁定（"确认命中"的召回边界就是这里的阈值）；`rule_004` 给出原则与起步阈值，具体数值由方向 C 用评测集校准。

---

## 14. 测量有效性修正（2026-09-15，随 rule_002 一起暴露）

### 14.1 问题：网关抖动伪装成准确度回归

扩集后的第一次全量测量（74 例）里，**10 例（13.5%）请求被网关以 HTTP 500 拒绝**，走进既有的容错降级（`provider_error`）。旧口径把降级算作"答错"，于是同一次运行得出：

| 口径 | closed_set | negative | 总体 | 结论 |
|---|---|---|---|---|
| 旧（降级算答错） | 0.850 | 0.912 | 0.878 | 看起来是断崖式回归 |
| 新（只统计已落地判决） | **0.972** | **1.000** | **0.984** | 实际无回归，closed_set 与基线持平 |

**不修的话，棘轮会被网关抖动驱动**：nightly 每天红绿随机，团队会开始"顺手更新 baseline"，整个门禁失效。

### 14.2 改动（`tests/intent_eval/harness.py`）

1. **准确率只统计已落地判决**：新增 `applied_pass_rate`（按落地次数算的通过率）、`scored_cases` / `unscored_cases`；桶的 `n` 改为"该桶落地用例数"。
2. **抖动率只统计落地 ≥2 次的用例**：降级的那一次 repeat 不再被误判为"结论翻转"（新增 `flippable_cases`）。这是 F5 度量的正确性修复 —— 否则 gateway 抖动会被读成模型不稳定。
3. **新增降级率门禁**（`fallback_rate`，阈值 2pt）：容忍降级 ≠ 放过降级。否则 F6 那类 provider 故障会以"容忍"的名义躲过所有检查（准确率分母被掏空，看到的全是绿灯）。
4. **新增薄样本保护**（`MIN_SCORED_RATIO = 0.5`）：某桶落地用例数低于基线该桶的 50% 时，该桶不参与棘轮判定，只出 note —— 防止"2 例全对"报出 100% 的假进步。
5. 新增 4 条离线测试钉住上述语义（降级不计入准确率 / 降级率单独门禁 / 降级 repeat 不算翻转 / 薄桶不棘轮）。

### 14.3 基线重建（显式、有理由）

口径变化 + 覆盖面 70→74 例，基线必须重建。按计划约定，重建是一次**显式且说明理由**的提交，不是"顺手更新"：

| 指标 | 旧基线 | 新基线 | 说明 |
|---|---|---|---|
| closed_set | 0.972 (n=36) | 0.972 (n=36) | 无回归 |
| negative | 0.988 (n=34) | 1.000 (n=28) | 分母变小是因 6 例降级被排除，不是覆盖缩水 |
| 总体 | 0.980 | 0.984 | — |
| fallback_rate | 未记录 | 0.135 | 首次记录，作为降级率门禁的参照 |
| 新增字段 | — | `scored_cases: 64` | 74 例中 64 例落地 |

### 14.4 运维发现（非代码问题，需要人处理）

该网关在本次测量期间对 74 次请求返回了 **10 次 HTTP 500（13.5%）**。因为降级是"容错放行"，含义是：**约 1/8 的对话轮次会完全跳过意图判定**（客户端退回 `corrected_text`，既不纠错也不判 `off_topic`）。对儿童产品不可接受。

门禁现在会盯住"降级率上升"，但**绝对水平需要排查网关/配额/上游稳定性**。建议为 `provider_error` 增加一次有界重试（1 次，带退避）——但那是生产代码改动，需单独裁定；本计划只把它记录在案。

**已处置（2026-09-15，用户裁定后实施）**：见 §14.6。

### 14.5 N=1 噪声余量（同批修正）

扩到 75 例后，一次 N=1 运行报出 closed_set −5.5pt / negative −3.7pt 双红。逐例核对后确认**没有真实回归**，全是三类已知噪声：

- `cs_040` 在"返回整句 / 返回候选"之间翻转（N=5 测量里它是唯一翻转用例）；
- `neg_017` 是首测就记录在案的不稳定用例（40% 翻转）；
- 本桶分母被降级削薄（negative 只剩 27 例）→ **一例就是 3.7pt**。

问题在于 **2pt 阈值本来是给 nightly 的 N=5 设计的**（`pass_rate` 按次平均，噪声被摊平）；拿它直接卡 N=1 等于"零容忍"，任何一个已知不稳定用例都会把门禁打红，团队随后就会开始"顺手更新基线"——棘轮失效的那条老路。

**修正**：`check_gate` 在 `repeats == 1` 时引入**噪声余量** = 1 例 / 本桶落地数，取 `max(2pt, 余量)` 作有效阈值。即"N=1 时单例退步算噪声，≥2 例退步才判失败"。N>1 不加余量（此时本来就该按平均后的比例判）。已在失败信息里显示实际生效的余量，避免阈值被偷偷放宽而不留痕。

同期还修掉评测器自身的两个缺陷：

- **`StubClient` 不是上下文敏感的**：它按 `raw_text` 索引期望值，而 `cs_040`/`cs_041` 同句不同问句 → perfect 模式假失败。改为按 `(raw_text, npc_question, candidate_answers)` 三元组索引（真实模型看得到上下文，假客户端也必须看得到），并加测试钉住。
- **薄桶棘轮**：见 §14.2 第 4 条。

**基线重建（N=5 代表值）**：先前基线来自 N=1 且覆盖 70 例，其中 `cs_040` 是"幸运通过"。改用 N=5 全量重建：

| 指标 | 旧基线 | 新基线 | 说明 |
|---|---|---|---|
| closed_set | 0.972 (n=36) | **0.933 (n=41)** | 差值全部由覆盖（+4 例含 2 个验收靶子）与 cs_040 的真实 pass_rate 解释 |
| negative | 1.000 (n=28) | 1.000 (n=34) | N=5 下 75 例全部落地评分 |
| 总体 | 0.984 | 0.963 | — |
| flip_rate | null | **0.013** | 唯一翻转用例 = cs_040（即 rule_003 的值形态问题） |
| fallback_rate | 0.135 | 0.136 | 与上次一致，网关仍在 ~13.6% 上失败 |
| repeats | 1 | **5** | 与 nightly 配置对齐 |

**新基线已把三个已知未过用例编码为现有水平**：`cs_009`（待 rule_001 落地）、`cs_040`（值形态不稳）、`cs_041`（待 rule_003 落地）。这正是棘轮的用法——它防的是**进一步**退步，而方向 C 的验收目标就是这三例。**没有发生任何代码或提示词改动**，本次 accuracy 变化纯属覆盖面与测量口径。

### 14.6 瞬时故障有界重试（已实施，2026-09-15，用户裁定）

§14.4 记录的问题（网关 ~13.5% HTTP 500 → 约 1/8 轮次完全跳过意图判定）按裁定实施了一次有界重试。

**范围与白名单**（`asr_postprocess._is_retryable_provider_error`）

| 故障 | 是否重试 | 理由 |
|---|---|---|
| 5xx（`APIStatusError.status_code >= 500`） | ✅ 1 次 | 网关/上游瞬时抖动，正是本次要治的 |
| 连接错误（`APIConnectionError`） | ✅ 1 次 | 同为瞬时 |
| 超时（`APITimeoutError`） | ❌ | **它是 `APIConnectionError` 的子类，必须先排除**；超时已吃掉孩子的等待与预算 |
| 4xx | ❌ | 配置/鉴权错误，重试只会掩盖它（F6 那种 BASE_URL 写错就是被掩盖的例子） |
| 响应形状漂移（走 `RuntimeError`） | ❌ | 配置问题，不是抖动 |

**核心安全性质**：重试花的是**同一个总时长预算**（`ASR_POSTPROCESS_TIMEOUT_MS`）。`_call_llm_with_retry` 接收绝对截止时间，每次尝试只取剩余预算，退避也被剩余预算 clamp——**重试永远不会延长孩子等待的上限**。若不这样设计，"一次重试"就等于把 30s 预算悄悄变成 60s。

**配置**：`ASR_POSTPROCESS_MAX_RETRIES`（默认 1，设 0 关闭）、`ASR_POSTPROCESS_RETRY_BACKOFF_MS`（默认 300，线性递增）。响应新增 `retry_count` 字段（额外请求数），降级与成功路径都带——运维因此能区分"第一次就失败"与"重试后仍失败"。

**测试**：`tests/test_asr_postprocess_retry.py`（14 条）钉住救回、有界（恰好 2 次调用）、可关闭、连接错误可重试、4xx/形状漂移不重试、**预算不可被延长**（400ms 预算 + 第二次挂 5s → 预算内收手）、退避生效且被预算 clamp。

**既有口径的取代**：原 `test_postprocessor_provider_error_does_not_retry`（"provider_error 一律不重试"）被本次裁定取代，改为 `..._5xx_retries_once_then_degrades`（断言恰好 2 次调用）；其保护性意图由两条新用例承接：4xx 不重试、超时不重试（后者原样保留、继续通过）。

**效果度量**（P1：改动必须可度量）：评测报告新增 `retries_total`（额外请求总数）与 `retry_recovered`（**本会降级、被重试救回来**的用例数）。nightly 的 `fallback_rate` 门禁（§14.2）同时是这条改动的主要验收指标——实施后该值应从 0.136 明显下降。若降级率不降，说明重试无效，应按数据回退而不是继续加次数。

**实测效果（2026-09-15，实施后首次 live N=1 全量 79 例）**

| 指标 | 实施前（N=5 基线） | 实施后（N=1） |
|---|---|---|
| `fallback_rate` | 0.136 | **0.000**（79 例零降级） |
| 重试次数 / 救回 | — | 9 次 / **9 例** |
| 总体准确率 | 0.963 | 0.937（N=1 噪声；门禁通过，closed_set −2.2pt 在噪声余量内） |
| 最慢单次 | — | 8.6s（该轮含一次重试） |

即本次样本里 9 个请求遇到瞬时故障，**全部**被一次重试救回：没有一轮再跳过意图判定。代价是这些轮次多发一次请求、最慢单次到 8.6s——远小于"整轮跳过判定"的代价。

**基线未因这次改善而更新**：改善不需要棘轮保护，且这只是 N=1 样本；`fallback_rate` 的参照值会在下一次 nightly N=5 时自然刷新。这正是"不顺手更新基线"的用法。

---

## 15. 部署与配置事故记录（2026-09-15）

### 15.1 现象

开发栈容器日志（`voice-service-1`）：

```
WARNING: [ASR-POSTPROCESS] provider runtime_error model=qwen3.8-27b-fp8 error=provider returned non-completion response: str
INFO:    [ASR-POSTPROCESS] response applied=False fallback_reason=provider_error intent=provide extracted_keys=[] latency_ms=458
```

第一行是 §11.3 F6 的守卫生效（不再 500）；第二行说明**每一次**请求都在降级，即 **意图判定功能在该容器上整体失效**。

### 15.2 根因链：配置没有随代码传播

| 事实 | 值 |
|---|---|
| 容器内有效 `ASR_POSTPROCESS_BASE_URL` | `https://tokens.netgpu.com`（**缺 `/v1`**） |
| 容器创建时间 | `2026-09-15T06:57:10Z`（≈北京 14:57） |
| 本机 `.env` 修复时间 | `2026-09-15T16:07:21`（北京） |

1. `.env` 被 `.gitignore` 覆盖（`.gitignore:12`）→ F6 的根因修复（补 `/v1`）**只落在开发机上**，未随代码传播到容器；
2. 容器创建于修复之前，且 `docker restart` **不会**重读 `env_file` —— 只有 **recreate** 才会。日志里的 `Up 3 minutes` 是重启，不是重建。

### 15.3 处置与验证

```
docker compose up -d --force-recreate voice-service
```

重建后容器内有效值变为 `https://tokens.netgpu.com/v1`，并在**容器内**用容器自己的 env 跑了真实 postprocess：

| 输入 | 结果 |
|---|---|
| `出发` | `applied=True intent=provide extracted={'answer': '出发'}` |
| `今天天气不错` | `applied=True intent=off_topic extracted={}` |
| `出发，继续` | `applied=True intent=provide extracted={'answer': '出发'}` ← rule_002 第 1 级生效 |

### 15.4 三条教训

1. **配置不走 git，就必然漂移。** 新增环境变量必须同时更新 `.env.example`（本次已做）并写进部署清单；`.env` 的改动必须配合容器 **recreate**，而不是 restart。
2. **F6 守卫把 500 变成了静默降级——正确，但不够响。** 降级率门禁（§14.2）能在 nightly 抓到，可部署环境里没人看 nightly。**已实施报警机制（见 §15.6）**：启动期 provider 探针 + `/health` 暴露 + 容器健康检查读该状态。
3. **镜像把 `.env`（含 API key）烘进了层。** `Dockerfile` 的 `COPY . .` + 构建上下文是整个服务目录 → `/app/.env` 703 字节随镜像分发，且那份**过期**的 `.env` 是暗雷（compose 的 `env_file` 目前盖得住，但只要某个变量漏写，`load_dotenv()` 就会用旧值静默生效）。已新增 `services/voice-service/.dockerignore` 排除 `.env` / `.venv` / `tests` 等；**需重建镜像才生效**，且建议评估该密钥是否已随镜像外流、是否需要轮换。

### 15.5 开发循环提示

`src` 以只读方式挂载（`./services/voice-service/src:/app/src:ro`）且 uvicorn 未开 `--reload`：

- **改代码** → 重启容器即可（模块重新加载）；
- **改 `.env`** → 必须 `--force-recreate`，否则进程仍用旧环境变量。

### 15.6 报警机制（已实施，2026-09-15）

针对教训 2 补了两条"让故障自己喊出来"的通道：

| 机制 | 位置 | 行为 |
|---|---|---|
| **启动期 provider 探针** | `src/main.py` startup → `ASRPostprocessor.check_provider()` | 发一个极小请求（`max_tokens=32`）；不是 completion / 超时 / 抛错 → `logger.error`，并把结论写进 `/health` 的 `postprocess` 字段 |
| **容器健康检查读该状态** | `Dockerfile` HEALTHCHECK | `/health` 的 `postprocess.status == "error"` → 退出码 1 → `docker ps` 显示 **unhealthy**（仍返回 HTTP 200，避免编排器重启风暴） |
| **响应预览** | `describe_non_completion()` | 非 completion 响应压成一行、截断 160 字符 —— 下次日志里直接看到 `<!doctype html>`，不必再猜 |

设计取舍：

- 探针**只在启动时**跑（另有 `GET /health?probe=1` 手动重跑），不做周期性探测：避免常态化的 provider 调用与状态抖动；持续性的退化由 nightly 的降级率门禁（§14.2）盯。
- 探针**绝不抛异常**（失败只描述），且用与真实请求**相同的 `(base_url, timeout)` 缓存键**取客户端，否则会把连接池挤退休、探针也失去代表性。
- 新环境变量 `ASR_POSTPROCESS_PROBE_TIMEOUT_MS`（默认 10000）已按教训 1 同步进 `.env.example`。

**验证（都在容器内用容器自己的 env 跑）**：

| 场景 | 结果 |
|---|---|
| 正确配置启动 | 启动日志 `provider probe ok base_url=https://tokens.netgpu.com/v1 latency_ms=3898`；`/health` → `postprocess.status=ok` |
| **反证**：注入坏 URL（缺 `/v1`）跑探针 | `status=error`，`reason=provider returned non-completion response: type=str preview=<!doctype html> <html lang="en"> …` —— 一次调用即定位根因 |
| 健康检查脚本逻辑 | `status=error` → 退出码 1；`ok` → 0；无该字段（旧版本）→ 0 |

> 注意：`Dockerfile` 的 HEALTHCHECK 改动**需重建镜像**才生效（当前运行中的容器仍用旧命令）；`/health` 的字段与启动探针已即时生效。

### 14.7 第二次基线重建（rule_004 落地时，2026-09-15）

`rule_004` 新增四个锚点用例（75→79 例），其中两个是**禁止侧验收靶子**，当前模型必然不通过（它会把漏词/语序错误纠正成满分答案）。基线随之重建，并做同口径归因：

| 指标 | 上次基线 | 新基线 | 说明 |
|---|---|---|---|
| closed_set | 0.933 (n=41) | **0.902 (n=45)** | 降幅全部来自新增的 `cs_044`/`cs_045` 两个靶子 |
| negative | 1.000 (n=34) | 0.993 (n=34) | `neg_017` 又抖了一次（该例 40% 翻转） |
| 总体 | 0.963 | 0.941 | — |
| flip_rate | 0.0133 | 0.0253 | 翻转用例 = `cs_040` + `neg_017`，与 §14.5 的判断完全一致 |
| fallback_rate | 0.136 | 0.144 | 该次测量的网关失败率（重试机制见 §14.6，在其落地后应会下降） |

**同口径对比证明零回归**：只看两次运行都存在的 75 例，准确率 **0.9633 → 0.9647（+0.1pt）**。closed_set 的 −3.1pt 完全由覆盖面解释，不是质量下滑。**这条"共同子集对比"应成为今后每次扩大覆盖时的标准举证方式**——否则每次加靶子都要从零论证，最后一定会有人干脆跳过论证。

**当前基线编码的五个已知未过用例 = 方向 C 的验收目标**：`cs_009`（rule_001）、`cs_040`（值形态翻转）、`cs_041`（rule_003）、`cs_044`/`cs_045`（rule_004）。（§14.5 里"三个已知未过用例"的说法已被本节取代。）

**`cs_043` 的校准数据**：`cs_042`（1 处编辑）与 `cs_043`（2 处编辑 / 13 字符 = 15.4%）当前模型**都通过**。因此若方向 C 采用 15% 起步阈值，`cs_043` 会从通过变成不通过——那是"规则层比模型更严"的**显式选择**，不是缺陷；数据支持把阈值提到 ~20% 以维持现状。两者都可接受，但必须显式决定并记录（已写入 `rule_004.calibration_data`）。

### 14.8 报告缺陷：`actual` 显示首次 repeat 而非首次落地（已修）

79 例 N=5 报告里 `cs_042` 显示 `actual.extracted = {}` 却 `applied_pass_rate = 1.0` —— 因为 `actual` 取的是**首次** repeat，而那次恰好降级。**差点据此把它误判为失败**（本轮分析时确实先误读了一次）。

已修为"取第一次**落地**的判定"，并加测试钉住；`fallback_reason` 仍作为诊断信息保留。这类"报表字段与指标口径不一致"的缺陷会让读数的人做出错误结论，代价比它看起来大。

### rule_005（原 `pr_006`，2026-09-15）：delegate 的成立条件是槽位声明可委托

**判据是槽位属性，不是句子形态。**

| 场景 | 结论 |
|---|---|
| 槽位声明 `delegatable: true`（带值池/提议模板）+「你帮我起一个吧」「随便选一个」「你决定吧」 | `delegate`（ADR-0001 原始场景，必须保住） |
| 未声明可委托的槽位（含封闭题）+「再换一个」「随便选一个」 | `off_topic` |

封闭题的 `candidate_answers` 只说明"有值池"，**不构成**可委托槽位。

**依据**

1. **代码事实**：全仓库 `delegatable`/`value_pool`/`pick_strategy` 只有一处声明（`BeginningFPController.gd:893-895` 名字槽），`intent == "delegate"` 只有一个消费者（同文件 496 行的名字完成器 `_propose_special_name`）。在封闭题输出 `delegate` = **没有完成器的标签**：`resume_confirm` 路径压根不读 `intent`（它用 `_is_resume_call(text)` 做 containment 判定），行为上与 `off_topic` 完全等价 —— 输出一个客户端做不到的意图，违反 A3。
2. **对 ADR-0001 的准确解读**：ADR 说"封闭题的 `candidate_answers` 视为值池的一个特例"是关于**值池**（委托时从哪里取值），而 ADR 同一节写明"值池、挑选策略、是否可委托，作为 `ExpectedSlot` 的扩展字段随请求传入"。把"有池"当成"可委托"是对 ADR 的过度解读 —— `pr_006` 的价值正是把这个混淆摊开。
3. **实测（探针 4 例）**：同一句「随便选一个」在未声明可委托的封闭题里被判 `delegate`、在可委托槽位上也判 `delegate`；而同一封闭题里「再换一个」却是 `off_topic`。两句同义而结论不同 → 模型按**句子形态**判、不按**槽位属性**判，现状不稳定。
4. **正面必须保住**：可委托槽位上三句当前都正确判 `delegate` —— 方向 C 收紧判据时不得把它们一起收掉。

**实现便利**：`delegatable` 与 `value_pool` **已经在 context 里透传、并已出现在 prompt 文本中**（`ExpectedSlot` 是 `extra="allow"`，已实测渲染确认）。**本裁定不需要改 src 的透传逻辑**，只需方向 C 在 prompt 措辞与规则层判据里显式使用该标志 —— 在 `src/` 正被并发修改的当下，这是一条"零 src 冲突"的裁定。

**边界澄清（由不变量测试逼出来的一条）**：委托的产物是**提议**，不是 `extracted`。在可委托的 `person_name` 槽位判 `delegate` 时 `extracted` 必须为空，**绝不**得把值池成员写进 `extracted` —— 否则等于把策划池里的名字冒充成孩子自报的名字（`rule_001` 自由槽例外在委托路径上的延伸）。

**锚点**：`cs_046`/`cs_047`（封闭题，须 `off_topic`）、`cs_048`–`cs_050`（可委托槽位，须 `delegate`）。其中 `cs_047` 与 `cs_049` **同句不同槽位、结论必须相反**，是"判据是槽位不是句子"的直接检验。

**顺带**：`person_name` 桶由本裁定**开桶**（3 例，仅覆盖委托路径）。计划 §5.2 要求的 50–70 例仍是 TODO，且 `pr_004`/`pr_005`（名字槽的否定句、报名字+反问）是该桶完整化的前置，仍待裁定。

### 14.9 第三次基线重建（rule_005 落地时）+ 有界重试的实测效果

`rule_005` 新增 5 个锚点（79→84 例）并**开 `person_name` 桶**。同口径归因：

| 指标 | 上次基线 | 新基线 | 说明 |
|---|---|---|---|
| closed_set | 0.902 (n=41) | **0.877 (n=47)** | 降幅来自 `cs_047`（封闭题「随便选一个」被判 `delegate`）与 `cs_046` 的翻转 |
| negative | 0.993 (n=34) | 0.988 (n=34) | `neg_017` 又抖了一次 |
| **person_name** | — | **1.000 (n=3)** | 新桶，rule_005 允许侧 3/3 正确 |
| 总体 | 0.941 | 0.926 | — |
| flip_rate | 0.0253 | 0.0357 | 翻转 = `cs_040` + `cs_046` + `neg_017` |
| **fallback_rate** | 0.144 | **0.024** | **并发写入者的有界重试落地后的重测**（见 §14.6） |

**同口径对比**：共同 79 例 **0.9411 → 0.9367（−0.4pt）** —— 持平，降幅由新增用例解释。

**retry 的实测效果（独立于本轮裁定，但很值得记录）**：本次 84×5 = 420 次调用里，有界重试触发 **51 次、救回 38 例**，`fallback_rate` 从 0.144 降到 **0.024**。这直接印证了 §14.4 的建议，也说明"容忍降级"在网关 ~14% 失败率下确实在吞掉约 1/8 的意图判定。基线现在把这个更严的水平记为参照 —— 任何回到两位数的降级率都会触发门禁。

**`cs_047` / `cs_049` 是"判据是槽位不是句子"的活体演示**：同一句「随便选一个」，在未声明可委托的封闭题里被模型判 `delegate`（错），在可委托槽位上也判 `delegate`（对）—— 两次输出完全相同，证明它按句子形态判。

**当前基线编码的已知未过用例 = 方向 C 的验收目标（8 项）**：`cs_009`（rule_001）、`cs_040`（值形态翻转）、`cs_041`（rule_003）、`cs_044`/`cs_045`（rule_004）、`cs_046`(部分)/`cs_047`（rule_005）、`neg_017`（已知 40% 翻转的上下文推理题）。

### rule_006（原 `pr_004`，2026-09-15）：填槽 + 附带提问仍算 provide，取值必须去壳且不含附带内容

**裁定**：玩家提供了槽位值、同时附带提问或寒暄（『我叫王小明，你呢？』）→ `intent = provide`，`extracted` = **名字本身**（『王小明』）而**不是整句**。自由槽允许"去壳归一"（`rule_001` 例外的具体化）：去掉『我叫 / 我是 / 我的名字是 / 叫我』这类引导词，并**必须同时丢弃附带内容**（反问、寒暄、语气词）。附带提问不改变意图——voice-service 没有 question 标签（A3），且槽位已被填。

**依据**

1. 判 `off_topic` 会把已经报出名字的孩子判成"没作答"（F2 误拒）——最坏的错法。
2. **取值必须是裸名，理由在客户端**：`_extract_name`（`BeginningFPController.gd:768-776`）只剥 `my name is / i am / i'm / 我是 / 我叫` 五个前缀。若 `extracted` 是整句『我叫王小明，你呢？』，剥壳后剩下的『王小明，你呢？』会经 `player_display_name` → `GameManager.set_player_info` → **`save_progress()` 持久化成玩家名字**，并被 NPC 台词模板与 ASR 上下文的 `user_id` 使用。
3. 前缀表里**没有『叫我』** —— 所以『叫我小明吧』这类表达，`extracted` 必须已经是裸名（『小明』），不能指望客户端再剥一次。
4. **实测 5 条探针全部正确**（我叫…你呢 / 我是… / 我的名字是… / 叫我…吧 / 裸名）→ 本裁定是**锁住已有正确行为**，防止方向 C 收紧判据时把"去壳 + 丢弃附带内容"一起收掉。

### rule_007（原 `pr_005`，2026-09-15）：含名字的否定句判 off_topic，绝不回填

**裁定**：含名字但整体是否定/拒绝（『我不想叫小明』『我不叫小明』）→ `intent = off_topic`，`extracted = {}`。名字槽与封闭题**同族同判**（对照 `cs_025`『我不想出发』）。

**依据**

1. **口径统一**：`cs_025` 已把否定句钉在 `closed_set` 桶的 `off_topic`；名字槽若适用相反口径，同一句话形态会因桶而异。
2. **数据完整性（比意图本身更严重）**：`extracted.name` 会经 `_extract_name` → `player_display_name` → `GameManager.set_player_info` → **`save_progress()` 落盘**。把『我不想叫小明』里的『小明』填进去 = 用孩子**明确拒绝的名字**给他命名并持久化，还会被 NPC 反复叫出来。
3. 否定句不构成填槽：它没有提供孩子的名字。
4. **不丢功能**：PROPOSED 态下对提议的拒绝由客户端 `_is_decline_utterance` 处理（英文整词匹配，避免 `Nolan`/`Nora` 误判）；真正的 `reject` 标签是方向 C 的契约扩展（ADR-0009），届时本裁定被**细化**而非推翻。

**`rule_006` 与 `rule_007` 是一对**：附带**提问**不改变意图，附带**否定**则改变。判据是"附带内容是否改变意图"，不是"是否附带内容"。两条都**不新增失败靶子**（当前全通过），价值在于把既有正确行为变成可回归的约束 —— 这是裁定的一种正当用法，与"纠正错误行为"同等重要。

### 14.10 增量合并：免去不必要全量重测的基线更新法

本次 `rule_006`/`rule_007` 新增 7 例且**全部通过**，各桶准确率不变，若仍按老办法全量重测（91 例 × 5 次 ≈ 455 次调用）纯属浪费。改用**增量合并**：在既有 84 例 N=5 结果之上，只对新用例跑一次 N=5（35 次调用），再用**两次运行的全部逐例数据**重算各桶准确率、总体、抖动率、降级率 —— 是精确重算，不是估计。

| 项 | 合并前 | 合并后 |
|---|---|---|
| person_name | 1.000 (n=3) | 1.000 (**n=10**) |
| closed_set / negative | 0.877 / 0.988 | 不变 |
| 总体 | 0.9262 | 0.9319 |
| scored_cases | 84 | 91 |
| flip_rate | 0.0357 | 0.0330 |
| fallback_rate | 0.0238 | 0.0220 |

**规则（写下来供复用，已修正一版）**：

- **新增/修改用例 → 一律用增量合并**。合并是对逐例数据的精确重算，归因天然成立：老用例的结果按定义不变，"降幅是否来自新用例"可以直接算出来（见 §14.11 的举证），不需要靠"共同子集对比"去反推。
- **只有代码或提示词变更后**才需要全量 N=5 重测 —— 那时旧结果不再代表当前版本，合并的前提（老用例行为未变）才真的不成立。
- 初版规则写的是"新增失败靶子就要全量重测"，那是**错的**：它在 §14.11 会强制一次约 500 次调用的重测，而换来的只是把老用例重新暴露在网关噪声里（归因反而更糊）。判断依据应该是"**被测代码变没变**"，不是"新用例通不通过"。

### rule_008（原 `pr_002`，2026-09-15）：候选值 + 额外内容 → provide + 候选值

**裁定**：玩家说出了某个候选、同时附带其他内容（自报姓名、寒暄、补充说明）→ `intent = provide`，`extracted` = **该候选的规范值**；附带内容不参与 `extracted`，但完整保留在 `corrected_text`。判据是**候选句本身是否完整、可复核地对齐**：完整 → 取候选（无论前后有多少附带内容）；候选**内部**被增删或乱序 → 转 `rule_004`。

**依据**

1. `rule_001` 的取值分工：`corrected_text` 保留玩家原话（供结构化过程回放），`extracted` 承载机器可读值；附带内容属于前者。
2. `rule_006` 已确立"附带内容不改变意图"；封闭题同理 —— 孩子确实说出了目标短语，客户端 containment 判定本来就会通过，判 `off_topic` 属 F2 误拒。
3. **实测暴露一个不对称**：模型会丢弃**前置**引导词，但**不**丢弃**后置**附带内容 ——

   | 输入 | 模型输出 | 判定 |
   |---|---|---|
   | `Say Nice to meet you` | `Nice to meet you` | ✓ |
   | `Repeat after me, nice to meet you` | `Nice to meet you` | ✓ |
   | `Nice to meet you, my name is Tom` | **整句** | ✗（`cs_058`） |

   规则层必须**两个方向都处理**，否则后置附带内容会一路进 `recent_turns` 与聚合。

### rule_009（原 `pr_003`，2026-09-15）：引导词按去壳处理，候选内部的增删仍禁止

**裁定**（细化 `rule_004` 的边界）：**候选之外**的内容（前置引导词『Say』『Repeat after me』『读』『跟我说』、后置附带内容）一律按去壳丢弃，**不**视为"多词"；**候选之内**的词数变化（漏词/多词）与词序变化仍禁止纠错，落到 `rule_003` 情形 2（保留 `provide`、清空 `extracted`）。

**依据**

1. 两类东西性质不同：引导词/指令回声是**孩子在复述老师的话**（或 ASR 把指令一起收进来了），不属于目标短语；而『Nice meet you』漏掉的是候选**内部**的 `to`，是学习错误。混为一谈要么误判孩子（多词即拒），要么放过错误（内部漏词也照修）。
2. **实测证明模型没有这条边界**：『Say Nice to meet you』与『Repeat after me, nice to meet you』它正确丢弃引导词；但『Say Nice meet you』它把候选**内部**的漏词也修好了（`cs_061`，5 次全错）—— 边界必须由规则层给。
3. 客户端 containment 对"前置引导词 + 候选完整"本来就会通过，所以这里的任务是把 `extracted` 收窄成候选值，而不是判分。

**`rule_004` 因此被细化**：其"词数变化"应读作"**候选内部**的词数变化"。已在 `rulings.jsonl` 里给 `rule_004` 加 `refined_by: rule_009`，避免只读到 `rule_004` 的人按严格读法把引导词也一起禁掉。

### 14.11 第二次增量合并：新增失败靶子也走合并（新规则的首个应用）

`rule_008`/`rule_009` 新增 4 例，其中 `cs_058`（后置附带内容返回整句，5 次里 3 次如此 → **翻转**）与 `cs_061`（候选内部漏词被修复，5 次全错）是新的验收靶子。按**修正后**的规则（§14.10）仍走增量合并 —— 只对新 4 例跑 N=5（20 次调用），再用三次运行的全部逐例数据精确重算。

**归因是算出来的，不是推出来的**：

| | 例数 | closed_set 准确率 |
|---|---|---|
| 老用例（未受新增影响） | 47 | **0.8766**（与旧基线逐位一致） |
| 新增 4 例 | 4 | 0.6000（`cs_058` 0.4 / `cs_061` 0.0） |
| 合并 | 51 | **0.8549** |

即 −2.2pt 全部由新增靶子解释，老用例的行为**一字未变**（同一份逐例数据，不存在重测噪声）。这比"全量重测 + 共同子集反推"更强。

| 指标 | 合并前 | 合并后 |
|---|---|---|
| closed_set | 0.877 (n=47) | 0.855 (n=51) |
| negative / person_name | 0.988 / 1.000 | 不变 |
| 总体 | 0.9319 | 0.9179 |
| scored_cases | 91 | 95 |
| flip_rate | 0.0330 | 0.0421（新增翻转 `cs_058`） |
| fallback_rate | 0.0220 | 0.0211 |

**方向 C 的验收目标增至 10 项**：`cs_009`、`cs_040`、`cs_041`、`cs_044`、`cs_045`、`cs_046`(部分)、`cs_047`、`cs_058`(部分)、`cs_061`、`neg_017`。

### rule_010（原 `pr_007`，2026-09-15）：附带内容**撤回**候选承诺时判 off_topic

**裁定**：候选口令之后紧跟**撤回性/迟疑性**内容（『等一下』『等等』『先别』『稍等』『算了』）→ `intent = off_topic`、`extracted = {}`。与 `rule_008` 的分工：**不撤回**的附带内容（寒暄、补充、同向加强）→ `provide` 并取候选值；**撤回**的 → `off_topic`。判据是**附带内容是否抵消了候选所表达的承诺**。

**依据**

1. **行为后果不对称**：`resume_confirm` 判 `provide` 会直接走 `_confirm_resume_from_room()` → **切场景**（把孩子传送走）；判 `off_topic` 只是提示 + 重问。孩子刚说完口令就喊停，此时传送走与他自己刚说的话直接矛盾，且切场景不可逆；重问一次的成本小得多。
2. 与 `rule_007` 同族：那条管"否定整个作答"，本条管"先作答再撤回"，都是**意图层**判断。
3. **实测**：『Let's go... 等一下』与『出发，等一下』模型都判 `provide` 并回填口令（两次都错）——它把口令当命中就收工，不看后面的撤回。而对照例『出发，我们走吧』（同向加强）判 `provide` 是对的 → 边界必须由规则层给，且**不能**简单地把"口令后有任何内容"都判 `off_topic`，否则会把 `rule_008` 一并推翻。
4. 客户端 `_is_resume_call` 用 containment，对"口令 + 等一下"本来就会通过 —— 只有意图标签能拦住误推进。

### rule_011（原 `pr_008`，2026-09-15）：内容层面的否定仍是作答；只有元层面的拒绝才是 off_topic

**裁定**：开放题里玩家**确实在回答问题**、只是内容为否定（『我今天没去集市』『我没看到』）→ `intent = provide`，`extracted.answer` = 玩家原话（自由槽，无可去之壳则原样保留）。判据是**是否在回答这个问题**，不是**内容是否肯定**。反过来，**元层面**的拒绝/不会/沉默填充（『我不想说』『不知道』『嗯……』）→ `off_topic`。

**依据**

1. 判 `off_topic` 会把一个诚实、切题的回答判成"没作答"，孩子被反复重问（F2）。而『我没去』恰是在回应问题的前提，NPC 完全应该接住（比如换个问法）。
2. 与既有已判例一致：`neg_002`『我不知道』/`neg_006`『我不想说』/`cs_025`『我不想出发』都是**元层面**（拒绝参与、不会、拒绝执行动作）→ `off_topic`；本条是**内容层面**的否定 → `provide`。界限：前者没有提供信息，后者提供了信息。
3. 与 `rule_007` 不冲突：那条禁止把孩子**拒绝的值**填进槽位（名字会被 `save_progress()` 落盘）；开放题里否定本身就是答案内容，`extracted` 承载的是玩家原话。
4. **实测模型已正确**（『我今天没去集市』→ provide + 原话）→ 本裁定同样是**锁住既有正确行为**，防止方向 C 在收紧"否定句"判据时把它一起收掉（`rule_007` 的否定家族很容易被过度泛化）。

**本裁定开 `open_slot` 桶**（开放题：无候选答案、无可委托值池）。计划 §5.2 要求的 40–60 例仍是 TODO。

### 14.12 第三次增量合并（裁定序列收尾）

并入 `rule_010`/`rule_011` 的 `cs_062`–`cs_067`：新 3 例 `closed_set` 中 `cs_065`/`cs_066`（口令后撤回）是靶子，`open_slot` 3 例全通过。

| 指标 | 合并前 | 合并后 |
|---|---|---|
| closed_set | 0.855 (n=51) | 0.826 (n=54) |
| negative | 0.988 (n=34) | 不变 |
| person_name | 1.000 (n=10) | 不变 |
| **open_slot** | — | **1.000 (n=3)**（新桶） |
| 总体 | 0.9179 | 0.9030 |
| scored_cases | 95 | 101 |
| flip_rate | 0.0421 | 0.0396 |
| fallback_rate | 0.0211 | 0.0198 |

---

## 15. 裁定序列收尾（2026-09-15）：11 条裁定，12 项验收目标

§11.5 第 1 步（裁定待裁定用例）**完成**：`cases_pending_ruling.jsonl` 现为空，11 条边界问题全部裁定，落成 **9 条 rule**（`pr_009`→`rule_001`、`pr_010`→`rule_002`、`pr_011`→`rule_003`、`pr_001`→`rule_004`、`pr_006`→`rule_005`、`pr_004`→`rule_006`、`pr_005`→`rule_007`、`pr_002`→`rule_008`、`pr_003`→`rule_009`、`pr_007`→`rule_010`、`pr_008`→`rule_011`）。

**裁定给出的确定性口径（方向 C 的实现依据）**

| 维度 | 口径 |
|---|---|
| 取值形态 | 封闭题取**候选规范值**；自由槽**保留原值**（去壳，禁止改写为池成员） |
| 多候选仲裁 | 本轮目标优先 → 最长 → 首次出现 → 表序 |
| 规则层权限 | 只收窄取值，**不覆盖意图**；取不到候选就清空 extracted，绝不改判 off_topic |
| 召回边界 | 纠**识别误差**（候选之外去壳 + 候选之内字符级近音），不纠**学习错误**（候选之内增删乱序） |
| 委托 | 需槽位声明 `delegatable`，不是"有候选表" |
| 附带内容 | 不撤回 → 取候选；**撤回/否定** → off_topic；元层面拒绝 → off_topic，内容层面否定 → provide |

**基线现状（N=5，101 例）**：closed_set 0.826 (54) / negative 0.988 (34) / person_name 1.000 (10) / open_slot 1.000 (3)；总体 0.903；flip_rate 0.0396；fallback_rate 0.0198。

**方向 C 的验收目标（12 项，全部已编码在基线里）**：`cs_009`（取值规范化）、`cs_040` + `cs_058`（值形态：整句 vs 候选）、`cs_041`（同句不同问句）、`cs_044`/`cs_045`/`cs_061`（学习错误被误纠）、`cs_046`/`cs_047`（delegate 判据是槽位）、`cs_065`/`cs_066`（撤回未识别）、`neg_017`（复读上一轮的上下文推理）。

**方向 C 待办清单**（按依赖顺序）

1. 规则层 `src/services/intent_rules.py`：意图判定 → 去壳（候选之外）→ 召回边界（候选之内，起步阈值 `max(1, 15%)`，`cs_043` 校准）→ 仲裁 → 候选择一；产出 `verdict_source="rule"`。
2. 契约扩展：`intent` 扩到 `provide`/`delegate`/`off_topic`/`accept`/`reject` + `matched_rule`/`shortcut_hit`/`shortcut_confidence`；**先写 `docs/adr/0009-*`**。
3. 客户端同步：`HybridAPI` 意图白名单、`BeginningFPController` 改读 `reject`（保留兜底）。
4. prompt 措辞：delegate 条件加"仅当槽位声明可委托"；去掉与规则层重复的取值规定（避免两个 owner）。
5. 实测并棘轮：跑通后 12 项验收目标应逐项转绿；**转绿是方向 C 的完成判据**。

---

## 15. 并发写入者裁定 pr_007/pr_008（2026-09-16 核对与勘误）

> 本节由本线（评测/裁定线）在发现与并发写入者撞号后补写，用于把两条独立裁定的关系、以及一处**事实性勘误**记录清楚。

**发生了什么**：本线在过 `pr_007`/`pr_008` 时，与并发写入者**独立裁定了同样两条**，并撞了同一批编号（`rule_010`/`rule_011` 与用例 `cs_062`-`cs_064`）。对方的版本已先提交，本线的追加在去重时被识别为同号而丢弃。结论：**采纳对方版本**（见下），本线只补充勘误与客户端 gap。

### 15.1 `rule_011`（`pr_008`）：两线结论一致

**开放题：内容层面的否定仍是作答（provide）；只有元层面的拒绝才是 off_topic。** 与本线独立得出的判据一致（"否定作用在答案内容上" vs "否定作用在作答行为上"），并各自写了对照用例（对方 `open_slot` 桶 `cs_062`/`cs_064`；本线 `cs_063` 等价物即对方的 `cs_062`）。**无分歧，取对方版本。**

### 15.2 `rule_010`（`pr_007`）：采纳对方结论，但必须附勘误

**分歧**：本线原判 `provide`（"犹豫属候选之外的后置内容，按 rule_008 去壳"）；对方判 `off_topic`（"迟疑/暂停/反悔 = 撤回承诺"）。

**采纳对方的理由**：对方的行为后果论证是决定性的 —— resume 路径上 provide 会直接 `_confirm_resume_from_room()` **切场景（不可逆）**，而 off_topic 只是提示 + 重问；孩子刚说完口令就喊停，此时传送走与他自己的话直接矛盾。**本线原判在语义上是错的。**

**勘误（本线核对代码后追加，已写入 `rule_010.correction`）**：对方 rationale 第 4 条称"这里只有意图标签能拦住误推进" —— **与当前代码不符**。核对 `BeginningFPController._on_asr_received`：`AWAIT_RESUME_CONFIRM` 在**任何 intent 判定之前**就 `await _handle_resume_asr_result(result); return`，而该函数只做 `_is_resume_call(text)`（containment），**完全不读 `intent`**。因此在当前客户端：

| 判定 | 客户端拿到的文本 | 结果 |
|---|---|---|
| `provide` + 口令 | `extracted`（含口令） | **出发** |
| `off_topic` + `extracted={}` | 退回 `corrected_text`（『Let's go... 等一下』） | 仍含 "let's go" → **照样出发** |

即：**`rule_010` 在客户端补上 intent 门控之前是行为空转的**。这条勘误的意义不是推翻裁定（语义上它是对的、数据记录也对），而是防止团队据此认为"犹豫已经被拦住了"——那正是最危险的状态：**以为处理了，实际没有**。

**客户端 gap（需产品决策，已写入 `rule_010.client_gap`）**：给 resume/出发路径加 intent 门控（`intent_matched` 为假时不走 `_confirm_resume_from_room()`），或收窄 `_is_resume_call` 使其要求"整句即口令"。

### 15.3 定标验证与基线合并（101 例）

用例集由对方扩到 **101 例**（新增 `cs_062`-`cs_067`：`rule_011` 的 3 条 `open_slot` + `rule_010` 的 3 条 `closed_set`），且 `src/` 在 2026-09-16 有提交（启动期探针 + 5xx 有界重试）。按修正后的合并规则（§14.10，"被测代码变没变"才是判据），先做**定标验证**：重测 10 项验收靶子 + 6 条新用例（16 例 × N=5）。

结果：**8/10 靶子逐位一致**，确定性失败项（`cs_009`/`cs_041`/`cs_044`/`cs_045`/`cs_047`/`cs_061`）全部 0.00 未变；仅两个**已知不稳定**用例向上浮动（`cs_046` 0.8→1.0、`neg_017` 0.6→0.8）。→ 09-16 的 src 改动**未影响判定行为**，合并前提成立。

| 指标 | 之前 | 现在 |
|---|---|---|
| closed_set | 0.855 (n=51) | **0.830 (n=54)** |
| negative | 0.988 (n=34) | 0.994 (n=34) |
| `open_slot`（对方开桶） | — | **1.000 (n=3)** |
| person_name | 1.000 (n=10) | 1.000 (n=10) |
| 总体 | 0.9179 | 0.9069 |
| scored_cases | 95 | 101 |
| flip_rate | 0.0421 | 0.0396 |
| fallback_rate | 0.0211 | 0.0198 |

**方向 C 验收目标增至 12 项**：`cs_009`/`cs_040`/`cs_041`/`cs_044`/`cs_045`/`cs_046`(部分)/`cs_047`/`cs_058`(部分)/`cs_061`/**`cs_065`/`cs_066`**/`neg_017`。其中 `cs_065`/`cs_066` 正是 `rule_010` 的靶子（模型对迟疑句一律判 provide），而对照 `cs_067`「出发，我们走吧」通过 —— 说明"口令后有内容"不能粗暴等同于撤回。
