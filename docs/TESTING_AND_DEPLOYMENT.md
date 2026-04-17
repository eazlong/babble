# LinguaQuest RPG — 测试与部署手册

版本: v0.1.0 | 日期: 2026-04-17

---

## 目录

1. [开发环境准备](#1-开发环境准备)
2. [项目结构与命令](#2-项目结构与命令)
3. [测试指南](#3-测试指南)
   - 3.1 单元测试
   - 3.2 E2E 测试
   - 3.3 性能测试
4. [本地部署](#4-本地部署)
5. [Docker 部署](#5-docker-部署)
6. [CI/CD 与云部署](#6-cicd-与云部署)
7. [环境配置](#7-环境配置)
8. [故障排查](#8-故障排查)

---

## 1. 开发环境准备

### 系统要求

| 依赖 | 最低版本 | 用途 |
|------|---------|------|
| Node.js | 20.x | 运行时 |
| pnpm | 10.x | 包管理器 |
| Docker | 24+ | 容器化部署 |
| CocosCreator | 3.8+ | 客户端开发 |
| Redis | 7.x | 消息队列（开发可用 Docker） |
| PostgreSQL | 16 | 数据库（开发可用 Supabase Local） |

### 首次安装

```bash
# 克隆仓库
git clone https://github.com/your-org/linguaquest.git
cd linguaquest

# 安装依赖
pnpm install

# 验证构建
pnpm build

# 运行测试
pnpm test
```

---

## 2. 项目结构与命令

### Monorepo 结构

```
linguaquest/
├── apps/
│   ├── game-client/          # CocosCreator 客户端 (TS)
│   └── parent-dashboard/     # Next.js 家长控制台
├── services/
│   ├── auth-service/         # 认证服务 (:8003)
│   ├── content-filter-service/  # 内容过滤 (:8004)
│   ├── dialogue-service/     # 对话引擎 (:8002)
│   ├── quest-service/        # 任务系统 (:8006)
│   ├── reward-service/       # 奖励系统 (:8007)
│   ├── spirit-coach-service/ # 精灵教练 (:8005)
│   └── voice-service/        # 语音管线 (:8001)
├── tests/
│   ├── e2e/                  # Playwright 端到端测试
│   └── performance/          # Vitest 性能基准
├── docker-compose.dev.yml    # 本地 Docker 环境
└── turbo.json                # Turborepo 配置
```

### 全局命令

```bash
pnpm dev          # 启动所有服务开发模式
pnpm build        # 编译所有项目 (Turborepo 并行构建)
pnpm test         # 运行所有单元测试
pnpm lint         # 代码检查
```

### 单项目命令

```bash
# 仅启动对话服务
pnpm --filter @linguaquest/dialogue-service dev

# 仅构建家长控制台
pnpm --filter @linguaquest/parent-dashboard build

# 仅运行游戏客户端测试
pnpm --filter @linguaquest/game-client test
```

---

## 3. 测试指南

### 3.1 单元测试

每个微服务包含独立的单元测试，使用 Vitest 运行。

```bash
# 运行全部单元测试
pnpm test

# 运行单个服务的测试
pnpm --filter @linguaquest/dialogue-service test

# 覆盖率 (需配置 vitest.config.ts 开启 coverage)
pnpm --filter @linguaquest/dialogue-service test -- --coverage
```

**当前测试覆盖**: 34 个测试用例，覆盖 7 个微服务 + 客户端核心模块

| 服务 | 测试文件 | 用例数 | 内容 |
|------|---------|--------|------|
| auth-service | `__tests__/register.test.ts` | 2 | 注册流程验证 |
| dialogue-service | `__tests__/npc-engine.test.ts` | 4 | NPC 对话引擎 |
| dialogue-service | `__tests__/llm-router.test.ts` | 3 | LLM 路由逻辑 |
| dialogue-service | `__tests__/health.test.ts` | 1 | 健康检查端点 |
| content-filter-service | `__tests__/moderation.test.ts` | 3 | 内容安全过滤 |
| quest-service | `__tests__/quest-engine.test.ts` | 3 | 任务状态机 |
| reward-service | `__tests__/drop-engine.test.ts` | 3 | LXP 掉落计算 |
| spirit-coach-service | `__tests__/error-detector.test.ts` | 3 | 语法错误检测 |
| game-client | `__tests__/ChildModeGuard.test.ts` | 9 | 儿童模式守卫 |
| game-client | `__tests__/TimeManager.test.ts` | 7 | 时间管理系统 |

### 3.2 E2E 测试

使用 Playwright 进行端到端集成测试，覆盖 4 大核心流程。

#### 前置条件

```bash
# 1. 安装 Playwright 浏览器
cd tests && npx playwright install

# 2. 启动基础设施
docker-compose -f docker-compose.dev.yml up -d

# 3. 启动所有微服务
pnpm dev

# 4. (可选) 设置测试环境变量
export TEST_API_TOKEN="your-dev-token"
export TEST_USER_ID="test-user-001"
```

#### 运行 E2E 测试

```bash
cd tests

# 运行全部 E2E 测试
npx playwright test

# 按项目运行 (仅桌面浏览器)
npx playwright test --project=chromium

# 仅运行语音管线测试
npx playwright test voice-pipeline

# 仅运行任务流程测试
npx playwright test quest-flow

# 生成 HTML 报告
npx playwright test --reporter=html
# 报告输出到 tests/e2e-report/，用浏览器打开查看

# 调试模式 (打开 Playwright UI)
npx playwright test --ui

# 录制测试
npx playwright codegen http://localhost:3000
```

#### E2E 测试覆盖矩阵

| 测试文件 | 测试场景 | 断言 |
|---------|---------|------|
| `voice-pipeline.test.ts` | 完整语音管线轮次 | NPC 响应非空、LXP 显示 |
| | 唤醒词触发精灵教练 | 教练 500ms 内出现 |
| | 5 秒沉默触发提示 | 教练提示可见 |
| | API 错误降级 | 回退消息显示 |
| `quest-flow.test.ts` | 接受并完成主线任务 | 任务完成、雷达图出现 |
| | 每日任务刷新 | 显示 3 个日常任务 |
| | 刷新后进度持久化 | 进度数字匹配 |
| `child-mode.test.ts` | 时间限制触发 | 警告→会话结束→总结 |
| | 内容过滤拦截 | 被过滤内容提示可见 |
| | 家长控制台查看 | 会话记录、进度图、词汇数 |
| | 调整时间限制 | 保存成功确认 |
| `reward-drop.test.ts` | LXP 奖励发放 | 奖励数值 > 0 |
| | 连续正确→徽章 | 连击徽章出现 |
| | 语法错误→教练纠正 | 纠正建议包含正确形式 |
| | 奖励面板展示 | 徽章列表、LXP 进度条 |

### 3.3 性能测试

使用 Vitest + 原生 `perf_hooks` 进行基准测试。

```bash
cd tests

# 运行性能基准测试
npx vitest run tests/performance/latency.test.ts

# 生成格式化性能报告
pnpm --filter @linguaquest/e2e-tests exec tsx ../scripts/performance-report.ts
# 或直接从根目录运行
cd .. && npx tsx scripts/performance-report.ts
```

#### 性能阈值

| 指标 | 样本数 | P95 阈值 | P99 阈值 | 说明 |
|------|--------|---------|---------|------|
| 语音管线 (ASR→LLM→TTS) | 100 | < 1500ms | < 2500ms | 完整对话轮次 |
| 唤醒词检测 | 50 | — | Max < 300ms | 精灵教练唤醒 |
| 精灵教练分析 | 50 | < 800ms | — | 语法错误分析 |
| 奖励发放 | 50 | < 200ms | — | LXP 计算与存储 |
| 内容过滤检查 | 50 | < 500ms | — | 文本安全检测 |

#### 性能报告输出示例

```
=== LinguaQuest Performance Report ===
Date: 2026-04-17T18:00:00.000Z
API: http://localhost:8002, Coach: http://localhost:8005

Metric               |      P95 |      P99 |      Avg |      Min |      Max |   Status
-----------------------------------------------------------------------------------------------
Voice Pipeline       |    1200ms |    1800ms |    980ms |    650ms |    2100ms | PASS
Wake Word            |     180ms |     250ms |    145ms |     80ms |     250ms | PASS
Coach Analysis       |     520ms |     680ms |    430ms |    290ms |     750ms | PASS
Reward Award         |     120ms |     150ms |     95ms |     60ms |     170ms | PASS
Content Filter       |     280ms |     380ms |    220ms |    140ms |     420ms | PASS

5/5 benchmarks passed
```

---

## 4. 本地部署

### 方式一：开发模式（推荐日常开发）

```bash
# 启动基础设施（Redis + PostgreSQL）
docker-compose -f docker-compose.dev.yml up -d

# 启动所有微服务（热重载）
pnpm dev

# 单独启动某个服务
pnpm --filter @linguaquest/dialogue-service dev    # :8002
pnpm --filter @linguaquest/auth-service dev         # :8003
pnpm --filter @linguaquest/parent-dashboard dev     # :3000

# 启动家长控制台 (Next.js)
pnpm --filter @linguaquest/parent-dashboard dev
# 访问 http://localhost:3000
```

### 方式二：开发会话脚本

```bash
# 启动并行开发会话 (Track A: 后端, B: 客户端, C: 家长控制台)
./scripts/start-dev-session.sh A    # 仅后端服务
./scripts/start-dev-session.sh B    # 仅客户端
./scripts/start-dev-session.sh C    # 仅家长控制台
./scripts/start-dev-session.sh all  # 全部启动
```

### 服务端口映射

| 服务 | 端口 | 健康检查 |
|------|------|---------|
| Voice Service | 8001 | `GET /health` |
| Dialogue Service | 8002 | `GET /health` |
| Auth Service | 8003 | `GET /health` |
| Content Filter Service | 8004 | `GET /health` |
| Spirit Coach Service | 8005 | `GET /health` |
| Quest Service | 8006 | `GET /health` |
| Reward Service | 8007 | `GET /health` |
| Parent Dashboard | 3000 | `GET /` |
| Redis | 6379 | `redis-cli ping` |
| PostgreSQL | 5432 | `pg_isready` |

---

## 5. Docker 部署

### 本地 Docker Compose

```bash
# 启动完整开发环境（数据库 + 消息队列 + 微服务）
docker-compose -f docker-compose.dev.yml up -d

# 查看日志
docker-compose -f docker-compose.dev.yml logs -f dialogue-service

# 停止所有容器
docker-compose -f docker-compose.dev.yml down

# 清理数据卷（警告：删除所有本地数据）
docker-compose -f docker-compose.dev.yml down -v
```

### 构建单个服务镜像

```bash
# 以 dialogue-service 为例
docker build -t linguaquest/dialogue-service:latest ./services/dialogue-service

# 运行容器
docker run -d \
  --name dialogue-service \
  -p 8002:8002 \
  -e DATABASE_URL=postgresql://postgres:postgres@host.docker.internal:5432/linguaquest \
  -e REDIS_URL=redis://host.docker.internal:6379 \
  linguaquest/dialogue-service:latest

# 验证健康检查
docker exec dialogue-service wget -qO- http://localhost:8002/health
```

### 生产 Docker Compose (待创建)

生产环境需要 `docker-compose.prod.yml`，包含：
- 反向代理 (Nginx/Traefik)
- TLS 证书
- 环境变量文件 (`.env`)
- 日志收集
- 监控 (Prometheus + Grafana)

---

## 6. CI/CD 与云部署

### GitHub Actions 流水线

当前 CI 配置 (`.github/workflows/ci.yml`)：

```
push/PR to main
  → checkout
  → setup Node.js 20 + pnpm
  → pnpm install --frozen-lockfile
  → lint (每个 service)
  → type check (tsc --noEmit)
  → test (vitest run)
  → upload coverage (dialogue-service)
```

**触发条件**: push 到 main 或 PR 到 main

**矩阵策略**: 6 个微服务并行执行

### 推荐的生产部署流程

#### 阶段一：容器化 + 手动部署

```bash
# 1. 构建并标记镜像
docker build -t linguaquest/dialogue-service:$(git rev-parse --short HEAD) ./services/dialogue-service
docker tag linguaquest/dialogue-service:$(git rev-parse --short HEAD) linguaquest/dialogue-service:latest

# 2. 推送到容器注册表 (ECR / GHCR)
docker push linguaquest/dialogue-service:latest

# 3. 在目标服务器上拉取并重启
ssh deploy@server "docker pull linguaquest/dialogue-service:latest && docker restart dialogue-service"
```

#### 阶段二：AWS Fargate (推荐生产)

```
GitHub → Actions → 构建镜像 → 推送 ECR
                ↓
          更新 ECS Task Definition
                ↓
          滚动部署到 Fargate Service
```

每个服务独立 ECS Task Definition：
- `dialogue-service`: 2-4 vCPU, 4-8 GB 内存
- `voice-service`: 4-8 vCPU, 8-16 GB 内存 (含 ASR/TTS)
- `spirit-coach-service`: 2 vCPU, 4 GB 内存
- 其余服务: 1 vCPU, 2 GB 内存

#### 阶段三：完整 CI/CD (待实现)

创建以下工作流：

```yaml
# .github/workflows/deploy.yml
on:
  push:
    branches: [main]
    paths: ['services/**']

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - checkout
      - setup-node + pnpm
      - build + test
      - configure AWS credentials
      - login to ECR
      - build + push Docker image
      - update ECS task definition
      - wait for deployment
      - run smoke tests against production
```

---

## 7. 环境配置

### 环境变量 (.env 示例)

```bash
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-service-role-key

# OpenAI (ASR + LLM)
OPENAI_API_KEY=sk-proj-xxxxx

# ElevenLabs (TTS)
ELEVENLABS_API_KEY=your-elevenlabs-key

# Redis
REDIS_URL=redis://localhost:6379

# 服务间认证
API_SECRET=your-api-secret
JWT_SECRET=your-jwt-secret

# 开发模式
NODE_ENV=development
LOG_LEVEL=debug
```

### 环境变量按服务分配

| 变量 | auth | dialogue | voice | content-filter | quest | reward | spirit-coach |
|------|------|----------|-------|---------------|-------|--------|-------------|
| SUPABASE_URL | ✓ | ✓ | | ✓ | ✓ | ✓ | ✓ |
| SUPABASE_KEY | ✓ | ✓ | | ✓ | ✓ | ✓ | ✓ |
| OPENAI_API_KEY | | | ✓ | ✓ | | | ✓ |
| ELEVENLABS_API_KEY | | | ✓ | | | | |
| REDIS_URL | | ✓ | ✓ | | ✓ | ✓ | ✓ |
| API_SECRET | ✓ | ✓ | | | | | |
| JWT_SECRET | ✓ | | | | | | |

---

## 8. 故障排查

### 构建失败

```bash
# 清除缓存重新构建
rm -rf node_modules .turbo apps/*/dist services/*/dist
pnpm install
pnpm build

# 单个服务排查
pnpm --filter @linguaquest/dialogue-service build
# 查看详细错误
pnpm --filter @linguaquest/dialogue-service exec tsc --noEmit --pretty
```

### 测试失败

```bash
# 单个服务测试
pnpm --filter @linguaquest/dialogue-service test

# E2E 测试调试
cd tests && npx playwright test --ui

# 性能测试 (服务未启动时预期失败)
cd tests && npx vitest run tests/performance/
```

### 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `app.error is not a function` | Fastify 使用 `app.log` 而非 `app.error` | 替换为 `app.log.error` |
| `Cannot find module 'cc'` | CocosCreator 模块不在 npm | 检查 `cc.d.ts` 是否存在 |
| `Cannot find module 'zod'` | 服务 package.json 缺少依赖 | 添加 `"zod": "^3.23.0"` |
| `Missing packageManager field` | Turborepo v2 要求 | 根 package.json 添加 `"packageManager"` |
| E2E 连接拒绝 | 服务未启动 | 先 `pnpm dev` 再运行测试 |
| pnpm 安装慢 | 未使用 lockfile | 使用 `pnpm install --frozen-lockfile` |

### 健康检查

```bash
# 检查所有服务健康状态
for port in 8001 8002 8003 8004 8005 8006 8007; do
  echo -n "Service on port $port: "
  curl -s http://localhost:$port/health | jq -r '.status' 2>/dev/null || echo "DOWN"
done
```

预期输出:
```
Service on port 8001: ok
Service on port 8002: ok
Service on port 8003: ok
Service on port 8004: ok
Service on port 8005: ok
Service on port 8006: ok
Service on port 8007: ok
```
