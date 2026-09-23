# LinguaQuest RPG (babble)

## 项目简介
面向儿童的语言学习 RPG 游戏。Godot 4.6 客户端 + Node.js/Fastify 微服务 + Python 语音/AI 服务 + PostgreSQL 数据存储。

## 当前状态
> 场景真相以 `apps/godot-client/project.godot` 与 `apps/godot-client/assets/scenes/` 为准。
> 旧三大场景（SpiritForest / SpellLibrary / RainbowGarden）与 MainMenu 的文件已删除。

已完成的场景与系统：
- 启动场景 ✅：`BeginningFP`（序章·主人房）——`project.godot:18` 的 `run/main_scene` 指向它；启动后按存档点续行到 `MirageInnIntroduction` / `ChangAnMarket` / `ChangAnMarketLesson02` / `MirageInnHub` / `WordSpiritLibraryArchiveHall`
- 场景导航系统 ✅ (固定启动场景 + 存档点续行 → 场景互跳；无"动态选择主场景")
- quest-service 事件驱动同步 ✅ (QuestEngine 幂等上报、离线韧性)
- assessment-service 真实评估集成 ✅ (规则打分：关键词匹配、文本长度、词汇多样性；36 测试通过)
- reward-service 联动 ✅ (reward-client with fallback)
- 日常任务完整实现 ✅ (任务池、动态生成、每日重置、GET/POST 接口)
- spirit-coach-service LLM 教练 ✅ (LLMCoach + PromptBuilder + StreakTracker + CoachQualityJudge + Metrics；160 测试通过 / 14 个测试文件)
- summary-service 学习总结与掌握度 ✅ (11 条路由，已合并 main 并入 compose；60 测试通过)

下一步：
- 测试覆盖补充、Supabase 迁移执行（018/019）、端到端联调
- voice-service 完整 Python 套件（210 项）仍未接进 CI（`ci.yml` 只跑 3 文件的离线子集）
- 待修：Godot 内部枚举 `SceneState` 与引擎内置类撞名，4 个测试文件（38 项）静默未被 GUT 收集

家长控制台 MVP 已完成 ✅：
- 前端：登录/注册、AuthGuard 路由守卫、响应式 Navbar、Dashboard/Reports/Settings 页面
- 后端 auth-service：8 条路由（health、login、register、dashboard、reports、time-limit、diagnosis、delete-data）
- 数据库迁移 018：scene_access JSONB + is_active 列
- 前后端 API 对齐：login 返回 token+parent_id，register 支持 child_name 并返回 token

### 已知缺口（动手前先读）
- **进度不落盘**：quest / reward / content 三个服务是内存态，重启即丢；`SupabaseQuestStorage` 只有测试在用。
- **CoachOverlay 未接线**：7 状态状态机实现在 `CoachOverlay.gd`，但没有任何场景实例化它，教练干预目前无 UI 出口。
- **未容器化**：content、content-filter、quest、reward 四个服务没有 Dockerfile，也不在 compose 里。
- **`pnpm lint` 全线不可用**：7 个 Node 服务的 `lint` 脚本调用 `eslint src/`，但仓库既无该依赖也无配置。
- **端口冲突**：content-service 与 assessment-service 都声明 8308。
- **测试覆盖不齐**：`pnpm test` 只跑 7 个 Node 服务；Python 服务与 E2E 需各自单独执行（见「测试」）。

## 技术栈
- **客户端**: Godot 4.6 (GDScript) + CocosCreator 3.8+ (TypeScript) 双客户端
- **云端核心**: Node.js/Fastify 微服务
- **AI 服务**: Python/FastAPI
- **数据库**: PostgreSQL（compose 内的 `postgres`；仅 auth-service 通过 `pg` 连接），Supabase 是规划中的托管目标、当前未接入
- **消息队列**: Redis Streams
- **外部服务**: OpenAI API (GPT-4o + Whisper), ElevenLabs TTS, F5-TTS (本地 MLX)
- **家长控制台**: Next.js

## 目录结构
```
services/                # 12 个目录（11 个微服务 + db 迁移）
  dialogue-service/      # 对话引擎 + LLM 路由 + Redis
  voice-service/         # ASR/TTS (Whisper + ElevenLabs) + 目标意图判定规则层
  spirit-coach-service/  # 精灵教练 Agent (hint/trigger/intervention)
  summary-service/       # 学习总结与掌握度
  f5-tts-server/         # 本地 F5-TTS (Mac MLX)，无 Docker
  auth-service/          # 认证 + 家长控制台后端
  content-service/       # 内容管理（内存态）
  content-filter-service/# 内容过滤
  quest-service/         # 任务系统（内存态，含 WS 推送）
  reward-service/        # 奖励（内存态）
  assessment-service/    # 评估
  db/migrations/         # 001–019 迁移；runner 见 scripts/run-all-migrations.sh
apps/
  godot-client/          # Godot 4.6 客户端 (主要)
    project.godot        # run/main_scene = res://assets/scenes/BeginningFP.tscn
    assets/scenes/       # 5 个场景 + 归卷厅 + components/ + ui/
    assets/scripts/      # autoload/ (17 个) + components/ + ui/ + core/
    .claude/             # Godot 专属 agents + skills（本地文件，未纳入 git）
    design/gdd/          # 游戏设计文档（约 15 份 + reviews/）
    test/ + tests/       # GUT 单元测试
  game-creator/          # CocosCreator 客户端（2026-05 起停摆，逐步迁移中）
  parent-dashboard/      # 家长控制台 (Next.js)
tests/                   # E2E 测试 (Playwright) + 性能测试
docs/                    # 架构文档、ADR、plans、agents、API 规格说明
scripts/                 # 开发辅助脚本 + 迁移 runner
```

## 快速启动

### 环境变量（根目录 `.env`，未被 git 跟踪）
- `OPENAI_API_KEY` — GPT-4o + Whisper
- `ELEVENLABS_API_KEY` — TTS
- `DATABASE_URL` — Postgres；compose 默认 `postgres://postgres:postgres@postgres:5432/linguaquest`
- `JWT_SECRET` — auth-service 签发/校验 JWT
- `services/voice-service/.env` — 语音服务专用配置（模板见 `.env.example`）

### 开发启动
```bash
# 1. 启动基础设施 + 已容器化的服务（redis / postgres / dialogue / voice /
#    spirit-coach / summary / auth / parent-dashboard）
docker compose up -d

# 2. 本地启动 F5-TTS（Mac ARM64，docker 不支持）
.venv/bin/python services/f5-tts-server/main.py

# 3. 启动 workspace 内的 Node 服务（turbo 并行）
pnpm dev

# 4. 打开 Godot 编辑器；导入 apps/godot-client，点击运行（启动场景 BeginningFP）
```

## 常用命令
```bash
pnpm dev                          # turbo 并行启动 workspace 内的 Node 服务
pnpm build                        # 构建
pnpm test                         # vitest：只覆盖有 test 脚本的 Node 服务
pnpm --filter "./services/quest-service" test   # 单服务测试
pnpm lint                         # 全线失败：7 个服务执行 `eslint src/`，而 eslint 未安装
docker compose up -d              # Redis + Postgres + 已容器化的服务
```

`pnpm --filter` 的路径选择器**必须带 `./` 前缀**：写成 `services/x` 会被当成包名，
匹配不到时只打印 "No projects matched the filters" 并 **exit 0**，导致步骤静默空转。

## 架构要点
- **语音管线**: VAD → ASR (Whisper) → LLM (GPT-4o) → TTS (ElevenLabs / F5-TTS)
- **实时通信**: Godot 客户端通过 WebSocket 与后端通信，Redis Streams 解耦语音/对话/教练事件
- **精灵教练 Agent**: Redis Streams 异步闭环 — dialogue_turn/silence/wake 三种触发器 → 冷却策略 (20s/30s) → 中英双语提示
- **CoachOverlay**: Godot 客户端 7 状态表示层，优先级门控状态机 + tween 生命周期管理 + 气泡显示（实现完整，**尚未被任何场景实例化**——见「已知缺口」）
- **双客户端**: Godot 4.6 (主要桌面/移动端) + CocosCreator 3.8+ (备用)，共享后端服务

## 测试
```bash
pnpm test                                 # vitest：只覆盖 7 个 Node 服务
pnpm --filter "./services/<name>" test    # 单服务测试（注意 ./ 前缀）
pnpm --filter tests exec playwright test  # E2E 测试 (Playwright，需完整栈)
scripts/godot-test.sh gut                 # Godot GUT 全量（headless）
```

**Python 服务不在 `pnpm test` 里**，必须进入服务目录单独跑（各服务自带 `pytest.ini`，
否则会误收集 `scripts/` 下的手动脚本）：
```bash
cd services/voice-service       && ../../.venv/bin/python -m pytest   # 210 passed / 3 skipped
cd services/assessment-service  && ../../.venv/bin/python -m pytest   # 36 passed
cd services/summary-service     && ../../.venv/bin/python -m pytest   # 60 passed
```

测试文件位置:
- 单元测试: `services/*/src/__tests__/`（Node）、`services/*/tests/`（Python）
- E2E 测试: `tests/e2e/`
- 性能测试: `tests/performance/`
- Godot GUT: `apps/godot-client/test/` 与 `apps/godot-client/tests/`

## 开发注意事项
- 优先修改 Godot 客户端 (`apps/godot-client/`)；CocosCreator 客户端自 2026-05 起未再提交，迁移已实质停摆
- F5-TTS 仅在 Mac ARM64 (MLX) 上本地运行，docker compose 中已注释
- `scripts/start-dev-session.sh` 仍可用，但其中的「轨道 B」等 prompt 仍指向 CocosCreator，与当前主线不符
- CI 矩阵只覆盖有 `package.json` 的 7 个 Node 服务；Python 套件仅 voice-service 的 3 文件离线子集入 CI

## Agent skills

### Issue tracker

GitHub Issues（不处理外部 PR）。详见 `docs/agents/issue-tracker.md`。

### Triage labels

使用默认标签名。详见 `docs/agents/triage-labels.md`。

### Domain docs

multi-context（按服务划分）。详见 `docs/agents/domain.md`。

### Godot client specialists

`apps/godot-client/.claude/` 包含游戏开发专属 agents 和 skills。
注意该目录被 `.gitignore:70` 忽略，**只存在于本地工作树**——干净克隆里没有它。

**Agents（游戏设计 + 实现）**：`game-designer`（核心循环、MDA/Flow/Bartle）、
`gameplay-programmer`（设计→代码、数据驱动、状态机）、`economy-designer`（资源流动、
战利品表、进度曲线）、`systems-designer`（公式、交互矩阵、变量表）、
`narrative-director`（故事架构、世界观、角色）、`writer`（对话文本）、
`godot-specialist`（引擎权威：Node/Scene、信号、性能）、`godot-gdscript-specialist`
（GDScript 质量：静态类型、设计模式、协程）。

**Skills（设计验证）**：`/balance-check`（平衡分析）、`/design-review`（GDD 完整性审查）、
`/prototype`（原型验证 + PROCEED/PIVOT/KILL）、`/quick-design`（小改动规格）、
`/godot-fix`（Godot 4.6 API 兼容性已知坑）、`/godot-debug`（版本确认→信号验证→最小场景）。
另有 `brainstorm` / `consistency-check` / `design-system` / `code-review` / `perf-profile` /
`qa-plan` / `regression-suite` / `security-audit` / `smoke-check` / `test-flakiness` / `ux-review`。

**GDD 文档位置**：`apps/godot-client/design/gdd/`；索引见同目录 `systems-index.md`。
