# LinguaQuest RPG 项目进度审核报告

| 项 | 值 |
|---|---|
| 审核日期 | 2026-09-16 19:42–19:50 CST |
| 快照提交 | `8c5acb604e5bda32dce01663bb946667d8737936` |
| 分支 | `main`（领先 `origin/main` **42** 个提交，落后 0） |
| 工作树 | 120 项未提交（53 改 / 32 删 / 35 未跟踪），暂存区为空 |
| 审核方式 | 5 个并行专职 agent + 主审交叉复核；一切结论以**实际执行**为准 |

> **快照纪律声明**：本仓库存在**并发写入者**。审核期间 HEAD 从 `6683091` 自行前进到 `8c5acb6`（19:43 新增 2 个 feifei 提交；提交 `2ae929b` 的标题即为「与并发写入者撞号后的核对」）。本报告所有数字描述 `8c5acb6`；若你读到时有新提交，请以提交时间为界重取。

> **2026-09-17 追记**（发布后 ~15 小时的动态，主审核实）：并发写入者已落实本报告的主要建议——`62dd457` 修复 R1（db.ts/jwt.ts/Dockerfile/sql 入库，auth-service 可构建）、`5cb11f5` 修复 R4（quest WS 改 v10 签名，tsc 干净、测试 43 全绿）、`7bef87f` 修复 CI 矩阵（现含 auth/content/content-filter 共 7 个服务）、重写 CLAUDE.md 状态块（采纳第六节勘误）、并已推送（本地领先从 42 降至 12）。正文保持快照原貌；本次勘误审核修正了正文中 4 处错误（已就地标注〔勘误〕）。

---

## 一、审核团队与方法

按要求组建了 5 个专职 agent 并行审核，主审（本报告作者）负责交叉复核与裁断：

| Agent | 职责范围 | 关键动作 |
|---|---|---|
| **services-js** | 7 个 Node/TS 微服务 | 逐个跑 vitest + `tsc --noEmit` |
| **services-py** | 4 个 Python/AI 服务 | 逐个跑 pytest（root `.venv`） |
| **godot-client** | Godot 4.6 客户端 | GUT 全量套件 + 主场景 headless 启动 |
| **repo-hygiene** | git/分支/集成/迁移/CI | 悬空引用 UID 解析、未跟踪依赖边 |
| **docs-drift** | 文档 vs 代码 | 逐条核验 CLAUDE.md 声明、ADR、plans |

**已实际执行**（非阅读推断）：10 个服务的测试套件（7 个 Node/TS + 3 个 Python；f5-tts-server 无测试、db 仅迁移）、8 个类型检查（7 服务 + 家长端）、Godot GUT 全量、Godot 主场景 headless 启动、Playwright/CI/迁移清点、以及本报告所有交叉复核命令。〔勘误 2026-09-17：初版误写「12 个服务的测试套件」。〕

**工具链更正（影响所有后续测试）**：本机 **没有 `timeout`**。`timeout 300 <cmd>` 会立即报 `command not found` 且**静默退出 0、不产生任何输出**——两名 agent 的首批结果因此全部作废并重跑。可用替代：`perl -e 'alarm shift; exec @ARGV' 300 <cmd>`。另：`pnpm` 被沙箱拦截（corepack 需写 `~/.cache`），需 `COREPACK_HOME=/tmp/dsh-corepack pnpm ...` 或直接调 `node_modules/.bin/vitest`。

---

## 二、总体判断

**项目处于「单条主线深度攻坚 + 基础设施欠账累积」的状态。**

工程质量本身很高——当前前线（voice-service 目标意图判定）的严谨程度达到罕见水准：评测尺子、棘轮基线、双门禁、逐条裁定留痕、N=5 实测。测试面也基本健康：**已执行 794 项通过、8 项失败**。

但**仓库卫生已进入危险区**：42 个提交只在本地一块磁盘上，CI 从未构建过它们；而 `main` 上被提交的 auth-service **无法从干净检出构建**。同时 CLAUDE.md 的状态块约一个月未更新，13 条具体声明中 **5 条为假、3 条不准确**——它是新人与 agent 唯一的入口文档，正在主动误导。

一句话：**代码质量 A-，前沿攻坚 A，仓库可运维性 D，文档可信度 D。**

### 评分卡

| 维度 | 评级 | 依据 |
|---|---|---|
| 测试健康度 | **B+** | 794 通过 / 8 失败；但 38 个 Godot 测试静默未收集，auth-service 测试为空转 |
| 前线攻坚质量 | **A** | intent 判定 0.948 → **1.000**（N=5/104 例，抖动 0.000），棘轮纪律严格 |
| 后端完成度 | **B-** | 接口齐全、测试绿；但 4/11 服务未容器化，quest WS 实际不可用 |
| 客户端完成度 | **B** | 可干净启动，228/236 GUT；CoachOverlay 运行时死代码 |
| 数据持久化 | **C** | quest/reward/content 全内存态，Supabase 存储层是死代码（重启丢进度） |
| 仓库可运维性 | **D** | 42 未推送、0 CI 覆盖、干净检出构建失败、迁移编号三目录冲突 |
| 文档可信度 | **D** | CLAUDE.md 5/13 声明为假（另 3 条不准），7 个 CONTEXT.md 死链，tickets.md 全框未勾而实已做完 |

---

## 三、量化快照

### 规模

| 指标 | 数值 |
|---|---|
| 跟踪文件（去 node_modules） | 1,310 |
| GDScript | 40,949 行 / 189 文件（其中 GUT 自带 82 文件 18,941 行；一方 68 文件 18,748 行） |
| TypeScript（services src） | 9,813 行 / 123 文件 |
| Python（services src） | 4,296 行 / 102 文件 |
| 服务 | 11 个服务 + `db`（仅迁移）+ 3 个 app |
| Godot 场景 / Autoload | 6 个 / 17 个 |
| 游戏内容 | 5 个对话流、98 条 flow、16 个词灵、2 个课节配置 |

### 测试执行结果（全部实跑）

| 层 | 文件 | 测试 | 结果 |
|---|---|---|---|
| Node/TS 微服务（7） | 29 | 260 | **260 通过 / 0 失败** |
| Python 服务（3 有测试） | 22 | 309 收集 | **306 通过 / 3 跳过 / 0 失败** |
| Godot GUT | 25 脚本 | 236 收集 | **228 通过 / 8 失败** |
| **已执行合计** | — | — | **794 通过 / 8 失败** |
| Godot **未收集** | 4 文件 | **38** | 解析失败，静默丢失（见 R6） |
| E2E Playwright | 7 | 776 行 | **未执行**（需完整栈） |
| 性能测试 | 1 | — | 未执行 |

3 项跳过均为环境门控（1 项预算门禁、2 项需讯飞凭据与可写 `/models`），非代码失败。无任何测试需要真实 API key 或 Redis/Postgres 才能通过。

---

## 四、各子系统审核结果

### 4.1 后端 Node/TS 微服务（7 个）

| 服务 | 用途 | 测试 | `tsc` | Dockerfile | compose |
|---|---|---|---|---|---|
| auth-service | 家长端后端：register/login(JWT+bcrypt)、5 个家长 API | 6 / 0 | ✅ | ⚠️ **未跟踪** | ✅ 8310:8303 |
| content-service | 场景目录 + 内存态学习会话 | 11 / 0 | ✅ | ❌ | ❌ |
| content-filter-service | 儿童模式正则审核 | 3 / 0 | ✅ | ❌ | ❌ |
| dialogue-service | NPC 对话引擎 + LLM 路由 + 审核 + Redis | 9 / 0 | ✅ | ✅ | ✅ 8302 |
| quest-service | 任务引擎、日常任务、WS 推送 | 40 / 0 | ❌ **5 错误** | ❌ | ❌ |
| reward-service | 掉落/XP/徽章，内存态 | 31 / 0 | ✅ | ❌ | ❌ |
| spirit-coach-service | LLM 精灵教练（触发器/冷却/提示/streak/指标） | 160 / 0 | ✅ | ✅ | ✅ 8305 |

**结论**：接口齐、测试全绿、单测极快（1.8–3.6 s）。问题不在「跑不跑得通」，而在**测试测了什么**与**部署得起来吗**：

- **auth-service 的 6 个测试不导入任何 `src/`**（只 `import { test, expect } from 'vitest'`）。`register.test.ts` 自造 mock、自调自断言；`diagnosis.test.ts` 自认「复制裁剪契约」因为 `trimItem/trimItems/trimBreakdown` 未导出。**401 行的 `parent-dashboard.ts` 与 `login.ts` 实质零覆盖**——而它正是家长控制台的全部后端。
- **4/7 服务未容器化**（content、content-filter、quest、reward）：无 Dockerfile、不在 compose。
- 端口 **8308 被双重占用**：content-service 监听 8308，而 Godot 客户端 `HybridAPI.gd:5` 与 compose 都把 8308 当作 Python assessment-service。本地起 content-service 会撞上客户端正在调用的端口。
- `lint` 在全部 7 个服务都是坏的：脚本写 `eslint src/`，但 eslint 与配置在任何地方都不存在。

### 4.2 Python/AI 服务（4 个）

| 服务 | 入口 | 测试 | 结果 |
|---|---|---|---|
| voice-service | FastAPI（ASR/TTS 网关 + intent 规则层） | 16 文件 | **210 通过 / 3 跳过 / 0 失败** |
| assessment-service | FastAPI 规则打分 | 1 文件 | **36 通过 / 0 失败** |
| summary-service | FastAPI 学习总结与掌握度（11 端点） | 5 文件 | **60 通过 / 0 失败** |
| f5-tts-server | FastAPI 本地 F5-TTS（Mac MLX） | 0 | 无测试、无测试配置 |

**这条线整体健康**，且纠正了两条 CLAUDE.md 声明（见第六节）。唯一功能空洞是刻意的第一阶段桩：`summary-service/src/api/routes/deep_assessment.py:90-93` 的 `POST /deep-assess/escalate-llm` 返回 **501**（ADR-0004 第二阶段待做）。

### 4.3 Godot 客户端（主客户端）

**可干净启动** ✅ —— `--quit-after 60` 退出码 0，17 个 autoload 全部初始化，无脚本/解析错误。仅有 `FeifeiBody` 叶骨 Bone2D 警告与强制退出泄漏提示（预期）。

**GUT：228 / 236 通过**，但真实分母是 **274**——4 个测试文件因解析失败被静默跳过 38 项。

**主场景真相**：`project.godot:18` → `res://assets/scenes/BeginningFP.tscn`。**不是**归卷厅。旧场景文件确已从盘上删除（退役属实），但退役不彻底：`GameManager.gd:28,35-38` 仍把 `MainMenu`/`SpellLibrary`/`RainbowGarden` 映射到 3 个已不存在的 `.tscn`；`WordSpiritLibraryArchiveHallController.gd:597` 留有指向 `MainMenu.tscn` 的死回退。

**CoachOverlay 是运行时死代码** ⚠️ —— 7 状态优先级门控状态机（427 行）本身是真的、写得不错，**但 6 个场景无一实例化它**，`CoachLayer` 节点在全仓库不存在，唯一消费者 `MainMenuController.gd` 自身零引用。后果：`DialogueManager` 里 `if coach_overlay:` 恒为假，**`CoachClient.intervention_received` 收到教练干预后没有任何东西渲染气泡**。已交叉复核确认（`grep CoachOverlay assets/scenes/` 为空）。

**真缺陷**：`RewardAnimation.gd:126` 访问 `VFXManager.VFXLayer`，该属性不存在 → 直接报错。

### 4.4 家长控制台（Next.js）

`tsc --noEmit` **干净通过** ✅。页面：login / register / dashboard / reports / settings + AuthGuard + Navbar；后端经 auth-service 代理诊断（ADR-0008），`summary-service` 不可用时降级 `{diagnosis:null,status:"generating"}` 而非 500——故障隔离做得对。护栏设置诚实标注「暂不强制执行」（ADR-0007）。

**但该 MVP 的骨架未入库**：`apps/parent-dashboard/Dockerfile`、`.dockerignore`、以及它唯一的 E2E 测试 `tests/e2e/parent-dashboard.test.ts` 全部未跟踪。「Content Control 页面」**不存在**——这是 PR #22 的**主动裁剪**（正文写明「砍 Content Control 页」「移除 content-settings 路由」），并非未实现。

### 4.5 内容与设计资产

GDD 15 份、AD 9 份、plans 18 份、5 个对话流（98 条 flow）、16 个词灵（双语词表）。垂直切片真实存在：序章主人房 → 蜃影客栈 → 长安市集课节 1/2 → 词灵归卷厅。规模是「一个完整章节」，不是全量产品。

**CocosCreator 客户端已实质停摆**：最后提交 **2026-05-21**（近 4 个月未动），228 个跟踪文件。CLAUDE.md 的「逐步迁移中」与实际不符。

---

## 五、当前前线工作（唯一活跃主线）

**`docs/plans/2026-09-15-intent-accuracy.md`** —— 目标意图判定准确度：评测尺子 + 确定性规则层。这是全项目质量最高的部分。

| 阶段 | 结果 |
|---|---|
| 首次度量（70 例，`qwen3.8-27b-fp8`） | 总体 0.980，抖动 0.0143 |
| 棘轮基线建立（101 例） | 总体 0.903；closed_set 0.826 为最差桶 |
| §18.2 规则层接入第一轮（104 例） | 0.948 —— **门禁失败** |
| **§18.3 第二轮（104 例）** | **全桶 1.000**；抖动 **0.000**（520 次测量零翻转）；降级率 0.0096 |

**值得记录的做法**：第一轮失败时，作者没有只看聚合数字，而是翻历史报告逐例取证，把「我改坏的」与「本来就抖的」分开，定位到根因「决策跑在 `corrected_text` 上」——即模型已把孩子的学习错误纠成正确答案，规则层再在纠错后文本上「确认命中」，等于把错误改写成满分。修法是把规则层输入拆成两个文本（决策用原始 ASR、自由槽表面形式用纠错文本），并沉淀出一般化教训：**模型与规则层串联时，规则层必须看到模型的输入，而不只是它的输出**。这正是 rule_004 立规矩要防的事，且只在接入生产路径时才暴露。

**〔勘误 2026-09-17，替换原「口径未对齐」段——原段为主审误判，计划文档的记账是自洽的〕**
第一轮 0.948 是真实的中间态。closed_set 各数完全自洽：§18 时点的该桶基线为 **0.811**（第一轮 0.921 = 0.811 + 11.0pt；第二轮 1.000 = 0.811 + 18.9pt，两处增量互相印证）。0.811 与 §905 记录的 0.826（101 例时点）不同，是因为 §15/§16 期间用例集扩编（cs_062–067）与校准决议（§16.5）触发了按规则的基线重建——这正是该计划「基线只随被测代码变更而更新」纪律的体现，不是记账错误。初版报告误把 docs agent 转录的「closed_set 0.811」当作第一轮测量值（实为 0.921），进而虚构了「口径未对齐」的叙事，特此更正并向计划作者致歉。

**已知遗留（作者自己列出）**：① 拼音/近音维未实现（`RuleOptions.phonetic` 只是配置项，无 `pypinyin` 依赖）；② `rule_010` 客户端门控需一次真人验收（说「出发，等一下」应被重问而非切场景）；③ 评测报告目录被 gitignore，**「结论在、证据没了」**；④ `shortcut_hit`/`shortcut_confidence` 未落地。

---

## 六、文档与实现的偏差（逐条已核验）

CLAUDE.md 是新人/agent 的唯一入口（**仓库根本没有根 README**），其状态块 13 条具体声明中 **5 条为假、3 条不准确**〔勘误 2026-09-17：初版误写「6 条失准」，与本表逐行判定不一致〕：

| # | 声明 | 判定 | 证据 |
|---|---|---|---|
| 1 | 主场景迁移为 `WordSpiritLibraryArchiveHall` | ❌ **假** | `project.godot:18` = `BeginningFP.tscn`；无任何代码动态设主场景 |
| 2 | 场景已现代化 ✅ | ⚠️ 不全 | 漏列 `MirageInnHub`、`ChangAnMarketLesson02`；退役名仍留在 `GameManager.gd` 注册表 |
| 3 | 场景导航系统 ✅（主场景动态选择） | ⚠️ 部分 | 无「动态选择」，实为固定启动场景 + 续行（`GameManager.gd:290`） |
| 4 | quest-service 事件驱动同步 ✅ | ✅ **属实** | `quest-storage.ts:58,189,401` 幂等；`quest-session-manager.ts:45,81` 离线队列 |
| 5 | assessment-service 36 测试通过 | ✅ **属实** | 实跑 `36 passed` |
| 6 | reward-service 联动 ✅ | ✅ **属实** | `reward-client.ts` + 6 个 reward 路由 |
| 7 | 日常任务完整实现 ✅ | ✅ **属实** | generate/daily/complete 三路由齐备 |
| 8 | spirit-coach **160 测试通过，含 10 个集成用例** | ⚠️ 数字对、细节错 | 实跑 **160 passed / 15 文件**；集成用例实为 **11** 个 |
| 9 | 进行中：summary-service **未合并 main** | ❌ **假** | `git rev-list --count main..feat/summary-service-mastery` = **0**；PR #21 已合并；27 文件在 HEAD；已入 compose |
| 10 | 待修复：voice-service **10 failed / 84 passed**（模块路径漂移） | ❌ **假** | 实跑 **210 passed / 3 skipped / 0 failed**，收集 213（非 94）。`src/api/routes/` 自首次脚手架就存在，路径本就正确，**没有漂移可修** |
| 11 | 家长控制台含 **Content Control** 页面 | ❌ **假** | 该页在 PR #22 被**主动砍掉**；`settings/page.tsx` 只有时长输入；无任何 `content` 引用 |
| 12 | auth-service **7 个端点（含 content-settings）** | ❌ **假**（成员错；数量口径存疑） | 不含 /health 的实际端点恰为 7 条（dashboard、reports、time-limit、**diagnosis**、delete-data、login、register）——数字碰巧对，**成员确定错**：`content-settings` 已在 PR #22 移除，却**漏列了 ADR-0008 的核心 `diagnosis` 端点**。〔勘误 2026-09-17：初版判「数量与成员双错」，系主审把 /health 计入导致口径不一。〕 |
| 13 | 数据库迁移 018：`scene_access` + `is_active` | ✅ **属实（且低估）** | `services/db/migrations/018_add_parent_dashboard_columns.sql:7,11,14`，另含 GIN 索引 |

**我亲自交叉复核的一条文档腐坏**：`docs/adr/0009` 第 185-186 行仍写着客户端改动「在**工作树**、提交时点取决于另一特性的落地」，但该工作早已由 `32c24f3` 提交（`git diff HEAD` 干净，`BeginningFPController.gd` 与 `HybridAPI.gd` 均无未提交改动）。ADR 是最高权威文档，却自称未提交——**这条会直接误导协作判断**。

### 其他文档完整性问题

- **`CONTEXT-MAP.md` 与 `docs/agents/domain.md` 链接 7 个不存在的 `CONTEXT.md`**（10 个里只有 3 个存在）。`domain.md` 还宣称 multi-context 布局运作良好，并漏掉了唯一真实存在的 `services/summary-service/CONTEXT.md`。
- **`tickets.md` 全部验收框未勾，而 Ticket 1–4 实际已完成且测试全绿**；T2 的验收标准要求集成到 **3 个已被删除的场景**。它还是**并行的第二套工单系统**——GitHub Issues（#5–#20，带标签）才是实际在用的。
- `tests/e2e/README.md` 写端口 **3300**，真实是 **3333**。
- `docs/plans/2026-04-16-mvp-implementation.md` 仍以 CocosCreator/AWS/Kong/Strapi 为架构（3003 行）；`2026-04-27-godot-phase2` 写「Godot 4.3 LTS」而项目是 4.6。
- **SRS 的 135 个需求 ID 无任何一条在代码或测试中被引用**，无一致性套件；抽查 `FR-V-005`（音素级评分/CMU 词典）与 `FR-A-001`（COPPA 可验证家长同意）均**未实现**。

---

## 七、风险登记册（按严重度排序）

### 🔴 CRITICAL

**R1 — auth-service 无法从已提交的树构建。**
`src/db.ts`（3,233 B）与 `src/jwt.ts`（1,162 B）**未跟踪**，却被 4 个**已跟踪**文件导入：`index.ts:7`、`middleware/auth.ts:2`、`routes/login.ts:4`、`routes/register.ts:5`。`git ls-files services/auth-service` 只有 9 个文件，二者不在其中。`sql/` 与 `Dockerfile` 同样未跟踪。
→ 干净克隆后家长控制台后端**编译失败**。而 CI 矩阵**恰好不含 auth-service 与 parent-dashboard**，所以这个问题对 CI 完全不可见。（已亲自复核）

**R2 — 42 个提交仅存在于本地一块磁盘，且从未被 CI 构建。**
`git rev-list --left-right --count origin/main...main` = **0 42**。`origin/main` 停在 **2026-08-18**。这 42 个提交包含 20 个 voice-service 裁定提交（rule_001–rule_011、ADR-0009、五值契约）与 14 个 Godot T6–T18 美术管线提交——**全部是新工作的唯一副本**。`ci.yml` 只在 push/PR 到 main 时触发，因此**这 42 个提交一次都没被构建过**。仓库有并发写入者，HEAD 在审核期间自行前进。

### 🟠 HIGH

**R3 — 5 个未跟踪文件是运行时承重件。**
`BeginningFPController.gd:15` 用 `const preload()` 加载未跟踪的 `wake_eye_open.gdshader`；`FeifeiBody.tscn:5` 以 `ext_resource` 指向未跟踪的 `BlinkController.gd`（该组件被全部 6 个场景使用）；`ChangAnMarketLesson02.tscn:9` 指向未跟踪的场景配置。**已提交的场景引用未跟踪的资产**——克隆即缺件。

**R4 — quest-service 的 `/ws/quest` 实际不可用。**
`tsc --noEmit` 报 5 个错误（已复核）：`quest-ws.ts:13,18,20,24` 使用 `@fastify/websocket` **v10 之前**的 `connection.socket` API，而实际安装的是 **10.0.1**（其运行时为 `wsHandler.call(this, socket, request)`）。`connection.socket` 为 `undefined` → **每次 WS 连接都抛错**。对照：spirit-coach 的 `coach-ws.ts` 用的是正确的 v10 写法且编译干净——两个 WS 路由写法不一致，quest 是坏的那个。

**R5 — CoachOverlay 运行时死代码，教练干预无 UI。**
见 4.3。状态机是真的，但没有任何场景实例化它 → `CoachClient.intervention_received` 收到干预后无处渲染。CLAUDE.md 把 CoachOverlay 列为已完成能力，与运行时事实相反。

**R6 — 38 个 Godot 测试静默未收集。**
`test_scene_management_system.gd`(18)、`test_game_hud.gd`(6)、`test_star_flight_animation.gd`(6)、`test_ui_framework.gd`(8) 解析失败。〔勘误 2026-09-17，机理修正〕真正原因不是「枚举与内置类撞名」，而是 **SceneStateMachine 重构后的测试腐坏**：`scene_management_system.gd:7` 已注释掉 `class_name SceneManagementSystem`（避免与同名 autoload 冲突），枚举也已改为 `enum State`（:23，委托给 `SceneStateMachine.State`）；而这 4 个测试仍按**旧 API**书写（`SceneManagementSystem` 作类型、引用已不存在的 `SceneManagementSystem.SceneState`，如 `test_scene_management_system.gd:32`）。Godot 4 存在内置类 `SceneState`，使报错信息更具迷惑性，但主因是测试未随重构更新。GUT 把解析失败误报为「does not extend GutTest」，**看起来像正常跳过**。真实成绩是 228/274，不是 228/236。

**R7 — 全部游戏进度都在内存里，重启即失。**
`SupabaseQuestStorage`（约 230 行）在生产代码中**从未被实例化**（仅测试使用），`QuestEngine` 默认 `MemoryQuestStorage`，`index.ts` 装饰了一个无人读取的 `app.supabase`。reward-service 与 content-service 同样内存态（后者因此有个 `/test/reset` 路由）。**对一个儿童学习产品，「今天的进度明天没了」是产品级缺陷，不只是技术债。**

### 🟡 MEDIUM

- **R8** auth-service 的 6 个测试不导入 `src/` → 家长端后端零覆盖（且 R1 使该后端连编译都过不了）。
- **R9** 端口 8308 双重占用：content-service 与 assessment-service/客户端冲突。
- **R10** 7 个 JS 服务的 `lint` 全坏（eslint 及配置均不存在）→ `pnpm lint` 全线失败。
- **R11** `.gitignore:83 design/` 未锚定，**静默吞掉 `apps/godot-client/design/gdd/` 下的新 GDD**（已 `check-ignore` 复核）；`:70 .claude/` 同样忽略掉 CLAUDE.md 里记载的 8 个专职 agent。
- **R12** 退役场景名仍留在 `GameManager.gd:35-38` 注册表 → 3 条死路径。
- **R13** voice-service 完整 210 项套件**不在 CI**（`ci.yml` 只跑 3 文件离线子集），真实回归不会被发现。
- **R14** `content-filter-service` 既无人调用又被重复实现：`dialogue-service/src/services/npc-engine.ts` 内的私有 `SimpleContentFilter` 正则表与它逐字相同——**活的是副本，服务本身是死重量**。
- **R15** 迁移编号跨 3 个目录冲突（005–008 各被用两次、内容不同；`001` 两次）；未跟踪的 `auth-service/sql/schema.sql` 是 `users.is_active` 的第二真相源。〔勘误 2026-09-17〕初版称「没有 runner」**有误**：`scripts/run-all-migrations.sh` 在快照时就存在（tracked，`8ca3d44`，bash 循环经 docker compose psql 逐个执行 `services/db/migrations/*.sql`）。runner 真实存在的遗留问题是：脚本头注释仍写「001-018」而 019 已存在；且它不解决三目录编号冲突与 schema.sql 重复。

### 🟢 LOW

- **R16** `deep_assessment.py:90-93` 的 `escalate-llm` 返回 501（ADR-0004 二阶段，刻意）。
- **R17** 规则层拼音/近音维未实现（行为安全，仅少一层背书）。
- **R18** `RewardAnimation.gd:126` 访问不存在的 `VFXManager.VFXLayer`（真缺陷）。
- **R19** 垃圾：未跟踪 `.scratch_persist.txt`（内容就是 `hello`）；**已跟踪**的 `demo.pcm`（72 K 全零裸 PCM）。
- **R20** 仓库膨胀：跟踪了约 **106 MB** Apple 系统字体（`STHeiti.ttc` 53 M + `STHeiti-Regular.ttf` 53 M，另有再分发授权问题）+ 6 张 2.9–3.6 MB PNG；未跟踪的 `feifei_part_副本.png`（2.6 MB）是 md5 不同的**陈旧图集变体**，需决定采用或删除。
- **R21** E2E 在**本机**可跑，但**无法从 `8c5acb6` 复现**（auth-service 起不来，见 R1）。`.worktrees/t_f2cd25f3` 无未提交内容、分支已并入 main → 纯陈旧占盘。

### ✅ 做得好的地方

- **密钥卫生干净**：898 个跟踪文本文件扫描，无任何真实 API key / JWT 字面量；真实 `.env` 均未入库，只提交 `.env.example`。
- **ADR 0001–0009 全部在代码中有真实落点**（非空头文档）：如 ADR-0003 半衰期 `0.5 ** (days/half_life)` 见 `mastery_engine.py:53,59`；ADR-0008 诊断代理见 `parent-dashboard.ts:243`。
- **故障隔离做对了**：summary-service 不可用时家长端降级而非 500。
- **测试套件快且稳**：JS 套件 1.8–3.6 s，Python 全部 < 25 s，适合做门禁。

---

## 八、建议行动（按优先级）

### P0 —— 今天做，防止不可逆损失

1. **推送。** `git push origin main`。42 个提交、含整条裁定语料与美术管线，只有一份本地副本。这是全报告中唯一「不做可能永久失去工作」的项。
2. **让 auth-service 可构建。** `git add services/auth-service/src/db.ts services/auth-service/src/jwt.ts services/auth-service/sql/ services/auth-service/Dockerfile apps/parent-dashboard/Dockerfile .dockerignore apps/parent-dashboard/.dockerignore` 并提交；随后**验证干净克隆能构建**。
3. **登记 5 个承重未跟踪文件**（R3），并把 4 个未跟踪的 Godot 测试与 `tests/e2e/parent-dashboard.test.ts` 一并入库。

### P1 —— 本周，止血 + 恢复可信度

4. **重写 CLAUDE.md 状态块**：删掉 voice-service「10 failed」与「summary-service 未合并」，修正主场景为 `BeginningFP.tscn`，端点表改为实际的 8 条（含 `diagnosis`、去掉 `content-settings`），删掉 Content Control 页的宣称。**先做这一条，因为它是 agent 与新人的共同入口，正在主动产生错误动作。**
5. **修 R4（quest WS）**：改用 `@fastify/websocket` v10 的 `connection` 形式，并从 spirit-coach 的 `coach-ws.ts` 取齐写法。
6. **修 R6（测试腐坏）**：把 4 个测试文件更新到重构后的 API（`SceneStateMachine.State`，或恢复一个不与 autoload 冲突的类型引用），让 38 个测试回到套件里；顺手修 `RewardAnimation.gd:126`。〔勘误 2026-09-17：初版建议「重命名内部枚举」，方向不对——枚举本身没撞名，是测试还停留在旧 API。〕
7. **把 auth-service 与 parent-dashboard 加进 CI 矩阵**，并为 voice-service 全套件接线（R13）。
8. **修 `.gitignore` 的 `design/`** 为 `/design/` 或 `!apps/godot-client/design/`，避免新 GDD 继续静默消失。

### P2 —— 本迭代，产品级风险

9. **决定持久化路线（R7）**：quest/reward/content 三处内存态对儿童学习产品不可接受。要么接通 `SupabaseQuestStorage`，要么显式记录「MVP 阶段可接受 + 何时必须做」。
10. **CoachOverlay 二选一（R5）**：接进场景（教练能力才真正可用），或从 CLAUDE.md 与 ADR 中降级为「已实现未接线」。**不要维持现状**——现状是文档说有能力、运行时无 UI。
11. **给家长端后端补真实测试（R8）**：至少覆盖 `parent-dashboard.ts` 的 D1 裁剪与降级路径。
12. **统一迁移记账（R15）**：删掉重复编号的三个目录中的两个，更新 `scripts/run-all-migrations.sh`（头注释仍写 001-018，需覆盖 019 并指明唯一目录），消除 `schema.sql` 第二真相源。
13. **补根 README**，并把 `pnpm test` 无法运行 Python 套件这一事实写清楚（CLAUDE.md 的快速启动目前对 Python 服务无效）。
14. **真人验收 `rule_010` 门控**（说「出发，等一下」应被重问而非切场景），并把评测报告目录改为滚动快照，避免「结论在、证据没了」。

---

## 九、审核置信度与未验证项

**高置信（实际执行）**：10 个服务的测试套件与 8 个类型检查（7 服务 + 家长端）、Godot GUT 全量与主场景启动、全部 git 状态/迁移/compose/CI 清点、R1/R3/R4/R6 的复核命令、密钥扫描、`design/` gitignore 复核、ADR-0009 陈旧声明复核。

**中置信（阅读推断）**：Godot 未跟踪件的「场景加载失败」后果系由 `preload`/`ext_resource` 引用边推断（未在真机观察装载失败）；各 plans 的状态归类依据内容+日期+文件存在性，未逐份复跑。

**未验证（报告不据此下结论）**：迁移 018/019 是否真正执行过（只确认文件存在、被跟踪、内容与声明相符）；Playwright 浏览器二进制与 3 个 `env_file` 是否齐备；意图判定 0.948→1.000 的**线上指标未复跑**（需 `INTENT_EVAL_LIVE=1` 与约 500+ 次真实 LLM 调用）——该结论来自计划文档自述，本次仅验证其**产物存在**（`rulings.jsonl` 14 行 = rule_001–rule_014、`intent_rules.py` 在位、`IntentLabel` 五值、提交 `8c90d1d`/`115897b`/`854b70f`/`6683091` 对得上）。

**审核期间未做任何仓库变更**（5 个 agent 均为只读；并发写入者的提交非本次审核所为）。
