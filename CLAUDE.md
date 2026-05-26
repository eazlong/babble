# LinguaQuest RPG (babble)

## 项目简介
面向儿童的语言学习 RPG 游戏。Godot 4.6 客户端 + Node.js/Fastify 微服务 + Python 语音/AI 服务 + Supabase 数据存储。

## 当前状态
CoachOverlay 7 状态表示层已完成。SpiritForest 场景 + MagicFlower/TreasureChest 组件已添加骨架。下一步：任务系统 (quest-service) + SpiritForest 任务逻辑集成。

## 技术栈
- **客户端**: Godot 4.6 (GDScript) + CocosCreator 3.8+ (TypeScript) 双客户端
- **云端核心**: Node.js/Fastify 微服务
- **AI 服务**: Python/FastAPI
- **数据库**: Supabase (PostgreSQL + Auth + Storage)
- **消息队列**: Redis Streams
- **外部服务**: OpenAI API (GPT-4o + Whisper), ElevenLabs TTS, F5-TTS (本地 MLX)
- **家长控制台**: Next.js

## 目录结构
```
services/                # 后端微服务 (11 个)
  dialogue-service/      # 对话引擎 + LLM 路由
  voice-service/         # ASR/TTS (Whisper + ElevenLabs)
  spirit-coach-service/  # 精灵教练 Agent (hint/trigger/intervention)
  f5-tts-server/         # 本地 F5-TTS (Mac MLX)
  auth-service/          # 认证
  content-service/       # 内容管理
  content-filter-service/# 内容过滤
  quest-service/         # 任务系统
  reward-service/        # 奖励
  assessment-service/    # 评估
apps/
  godot-client/          # Godot 4.6 客户端 (主要)
  game-creator/          # CocosCreator 客户端
  game-client/           # Web 客户端
  parent-dashboard/      # 家长控制台 (Next.js)
tests/                   # E2E 测试 (Playwright) + 性能测试
docs/                    # 架构文档、计划、规格说明
scripts/                 # 开发辅助脚本
```

## 快速启动

### 环境变量
需要配置以下 API key:
- `OPENAI_API_KEY` — GPT-4o + Whisper
- `ELEVENLABS_API_KEY` — TTS
- Supabase 项目 (Service Role Key)
- `services/voice-service/.env` — 语音服务专用配置

### 开发启动
```bash
# 1. 启动后端基础设施 + 微服务
docker compose up -d

# 2. 本地启动 F5-TTS（Mac ARM64，docker 不支持）
.venv/bin/python services/f5-tts-server/main.py

# 3. 启动所有服务开发模式
pnpm dev

# 4. 打开 Godot 编辑器
# 导入 apps/godot-client 项目，点击运行
```

## 常用命令
```bash
pnpm dev             # 所有服务开发模式
pnpm build           # 构建
pnpm test            # 运行所有测试
pnpm test --filter=<service-name>  # 单个服务测试
pnpm lint            # 代码检查
docker compose up -d # 启动 Redis + Postgres + 微服务
```

## 架构要点
- **语音管线**: VAD → ASR (Whisper) → LLM (GPT-4o) → TTS (ElevenLabs / F5-TTS)
- **实时通信**: Godot 客户端通过 WebSocket 与后端通信，Redis Streams 解耦语音/对话/教练事件
- **精灵教练 Agent**: Redis Streams 异步闭环 — dialogue_turn/silence/wake 三种触发器 → 冷却策略 (20s/30s) → 中英双语提示
- **CoachOverlay**: Godot 客户端 7 状态表示层，优先级门控状态机 + tween 生命周期管理 + 气泡显示
- **双客户端**: Godot 4.6 (主要桌面/移动端) + CocosCreator 3.8+ (备用)，共享后端服务

## 测试
```bash
pnpm test                          # 单元测试 + 集成测试 (vitest)
pnpm --filter tests exec playwright test  # E2E 测试 (Playwright)
```
测试文件位置:
- 单元测试: `services/*/src/__tests__/`
- E2E 测试: `tests/e2e/`
- 性能测试: `tests/performance/`

## 开发注意事项
- `start-dev-session.sh` 脚本仍可用 (`./scripts/start-dev-session.sh [A|B|C|all]`)
- F5-TTS 仅在 Mac ARM64 (MLX) 上本地运行，docker compose 中已注释
- 优先修改 Godot 客户端 (`apps/godot-client/`)，CocosCreator 逐步迁移中
