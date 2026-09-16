# 意图判定评测集（Path A MVP）

计划文档：`docs/plans/2026-09-15-intent-accuracy.md`

这套东西回答一个问题：**改了 prompt 之后，判定到底是变准了还是变差了，差在哪个桶。**

## 文件

| 文件 | 作用 |
|---|---|
| `contexts.json` | 场景上下文模板，形状从客户端真实构造点重建（每个模板都标了 `_source`） |
| `cases.jsonl` | 可判分用例：`closed_set` 36 条 + `negative` 34 条 |
| `cases_pending_ruling.jsonl` | **待裁定**用例：边界需要产品决策，**不计入门禁** |
| `rulings.jsonl` | **已生效裁定**：每条写清 decision / rationale / exception / 受影响用例 |
| `baseline.json` | 棘轮基线（首次由 `--update-baseline` 生成） |
| `harness.py` | 装载 / 判分 / 指标 / 门禁逻辑（被 runner 与 pytest 共用） |

## 怎么跑

```bash
cd services/voice-service

# 1. 离线自检：验证 harness 与门禁本身，零成本、不发网络请求
.venv/bin/python scripts/run_intent_eval.py --stub perfect --matrix

# 2. 看分桶与待裁定数量
.venv/bin/python scripts/run_intent_eval.py --list-buckets

# 3. 真实模型评测（读 .env 的 ASR_POSTPROCESS_* 配置，消耗预算）
.venv/bin/python scripts/run_intent_eval.py --max-calls 100 --json /tmp/intent_eval.json

# 4. 抖动率（nightly / slow 通道，N=5）
.venv/bin/python scripts/run_intent_eval.py --repeats 5 --limit 12 --max-calls 80

# 5. 棘轮：把当前结果写成新基线（必须是一次独立提交，进 review）
.venv/bin/python scripts/run_intent_eval.py --update-baseline
```

退出码：`0` 门禁通过 / `1` 门禁失败 / `2` 运行错误（含预算闸门拒绝）。

## 门禁规则

- **每桶退步 >2pt → 整体拒绝**（计划文档 §5.1）。看每个桶而不是总体，因为"一律判 off_topic"这类退化策略能拿满 `negative` 桶却在 `closed_set` 上崩掉，总体准确率会掩盖它（`tests/test_intent_eval_gate.py` 有专门一条用例钉住这点）。
- **抖动率上升 >2pt → 拒绝**。抖动率需要 `--repeats >1`，按计划只在 nightly/slow 通道跑 N=5，日常批次不跑（否则门禁一次要烧几十次调用）。
- **降级率上升 >2pt → 拒绝**。容忍降级 ≠ 放过降级：准确率只看已落地判决，所以必须有另一道闸看住 provider 故障，否则它会被"容忍"掩盖（F6 那类缺陷正是如此）。
- **基线与本次运行的模式必须一致**（`live` vs `stub:*`）。stub 基线不能给 live 结果当门禁，反之亦然——防止用假尺子量真东西。
- **`--bucket` / `--limit` / `--sample-per-bucket` 属于 partial 运行**：不参与棘轮，`--update-baseline` 会拒绝（除非 `--force`）。
- **`--max-calls` 是费用闸门**：计划调用数超限直接拒绝运行，不先花钱再报错。
- **薄桶不棘轮**：某桶落地用例数低于基线该桶的 50% 时，该桶只出 note、不判退步或进步（防止降级掏空分母后"2 例全对"报出 100% 的假进步）。
- **N=1 噪声余量**：`--repeats 1` 时有效阈值取 `max(2pt, 1 例占本桶的比例)` —— 即"单例退步算噪声，≥2 例退步才判失败"。2pt 阈值本是给 N=5 设计的（`pass_rate` 按次平均，噪声被摊平）；单次跑直接用它等于零容忍，任何已知不稳定用例（`cs_040` 值形态翻转、`neg_017` 40% 翻转）都会把门禁打红，随后就会有人"顺手更新基线"。**N=5（nightly）才是权威配置**，N=1 用于快速反馈。

## 指标口径（重要）

- **准确率只统计"已落地判决"的用例**（`applied=True`）。provider 降级（网关 500、超时等）不是模型的判决，把它算成"答错"会让网关抖动伪装成准确度回归——实测同一次运行因 13.5% 降级而虚报 -12pt（计划文档 §14）。
- **抖动率只统计"落地 ≥2 次"的用例**（`flippable_cases`）；某次 repeat 降级不算"结论翻转"。
- 降级单独上报为 `fallback_rate` / `unscored_cases`，由降级率门禁看住。

## 样本约定

- `provenance`：`agent_authored` / `human_handwritten` / `real_log`。
  **当前 74 条全部是 `agent_authored`**（由编码 agent 依客户端真实上下文形状编写，**不是**真实玩家语音，也不是运行期 LLM 采样）。这意味着分布偏差是真实存在的：儿童真实表达、口音、ASR 误听模式都未覆盖。计划文档 §8 要求的"20–30 条真实样本锚点"仍是 TODO。
- 每条样本必须有 `note`：说明它钉住什么失败模式。没有 note 的样本会在测试里被拒绝。
- 边界模糊的样本**不放这里**，放 `cases_pending_ruling.jsonl`，`ruling_question` 写清要裁定什么。用它避免"用一条自己也拿不准的样本去卡门禁"。
- 一期只有文字样本，`asr_confidence` 固定注入 `0.9`（干净音频假设）。音频集是二期。
- `verdict_source` / `shortcut_hit` / `matched_rule` 是给规则层（方向 C）预留的字段，现在恒为 `llm` / `False` / `None`。

## 裁定流程

1. 边界拿不准 → 进 `cases_pending_ruling.jsonl`（`expect: null`，写 `ruling_question`）。
2. 裁定后 → 写一条 `rulings.jsonl`（`id` / `decided_at` / `supersedes` / `decision` / `rationale` / `affects_cases`），**同时把该用例从待裁定集里移除**。
3. 被裁定影响的用例照旧进 `cases.jsonl` 判分；裁定的依据留在 rulings 里，契约层面的固化在 ADR（各条 `folds_into` 字段）。

已有裁定：

- **`rule_001`（原 `pr_009`）**：封闭题的 `extracted` 取**候选规范值**（阈值内 top-1，未达阈值判 `off_topic` 不猜）；**自由槽例外**——`person_name` / 无候选表时保留玩家说出的值，禁止改写成值池成员（`extracted.name` 会直接成为玩家名字）。`corrected_text` 保留玩家原话供回放，`extracted` 承载机器可读值。
  可执行形式见 `tests/test_intent_eval_gate.py::test_closed_set_expectations_are_canonical_candidates`——封闭题的期望值必须在候选表内，这条不变量挡住"把原话当期望值"的写法。
- **`rule_002`（原 `pr_010`）**：多候选命中的仲裁 —— **本轮目标优先 → 最长 → 首次出现 → 表序**，且 `extracted` 必须恰好等于某个候选（禁止整句）。第 3/4 级次序是依实测改判的（表序依赖客户端拼接两个列表的实现细节，脆弱）。`pr_011` 是它的直接下游。
- **`rule_003`（原 `pr_011`）**：模型返回非候选值时，**规则层只收窄取值、不覆盖意图** —— 能确认命中就改写为候选值（标 `verdict_source="rule"`），不能确认就清空 `extracted` 让客户端退回 `corrected_text`（保留模型的 `provide`），**绝不**因此改判 `off_topic`；反过来也**绝不**凭"句中出现候选"把 `off_topic` 翻成 `provide`（`cs_025`「我不想出发」就是反例）。依赖 `pr_001` 定下"确认命中"的召回边界。
- **`rule_004`（原 `pr_001`）**：召回边界 —— **纠识别误差，不纠学习错误**。允许：同词数、逐词对齐、差异仅在字符/音素层面（近音/拼读/错字），起步阈值 `归一化编辑距离 ≤ max(1, 15%×候选长度)`。禁止：漏词/多词、词序变化、否定反义、跨语义替换 —— 且**禁止纠错 ≠ 判 off_topic**（保留 `provide`、清空 `extracted`，由客户端三档 tier 给部分分）。锚点：`cs_019`/`cs_042` 必须纠错，`cs_044`/`cs_045` 必须不纠错，`cs_043` 是留在阈值之外的校准探针。

**为什么这条边界重要**：`extracted` 优先于 `corrected_text` 被客户端用作判定文本。把孩子的学习错误（`Meet you nice`）改写成满分句子，客户端连错误都看不到——教学纠错与掌握度统计会同时失效。这类改写是**篡改证据**，不是"宽容"。

**一处勘误（2026-09-15，同日自查）**：`pr_011` 的原始描述把模型返回值记作"拼接值 `mynameislilynicetomeetyou`"。原始输出其实是**带空格标点的整句原话**——那个无空格串是 `grade()` 打印失败原因时 `normalize_text()` 去空白标点后的**比较形式**。差别很关键：整句仍含候选短语，客户端 containment 判定照样通过，所以没有"误拒"风险，真正的缺陷是记录里存了整句而非规范值。`rule_003` 是依**勘误后的事实**裁定的。

裁定的下游：每裁定一条，常会浮出下一条。`pr_011` 就是 `rule_002` 直接暴露的：规则规定了"应该取候选"，没规定"取不到时怎么办"——而探针实测模型确实会返回拼接值（`mynameislilynicetomeetyou`）。

## 与 CI 的关系

- 离线门禁测试（`tests/test_intent_eval_gate.py`，无标记）随 `pnpm test` 常跑。
- 真实评测默认跳过，需显式开启：`INTENT_EVAL_LIVE=1 .venv/bin/python -m pytest -m intent_eval`
