# 家长控制台 Docker 容器化

版本: v1 | 日期: 2026-08-18

> 本文档描述如何把家长控制台 Web（Next.js `apps/parent-dashboard`）打包成 Docker
> 并纳入 `docker-compose.yml` 一起运行。

---

## 目录

1. [概览与架构](#1-概览与架构)
2. [涉及文件](#2-涉及文件)
3. [快速启动](#3-快速启动)
4. [环境变量](#4-环境变量)
5. [构建细节](#5-构建细节)
6. [端口与外部访问](#6-端口与外部访问)
7. [常见问题](#7-常见问题)

---

## 1. 概览与架构

家长控制台是 LinguaQuest 的家长端 Web 应用（Next.js 14 + React 18），只读消费
auth-service 暴露的家长 API（`/api/v1/parent/*`）。容器化后包含两个服务：

```
浏览器（宿主侧，代码在浏览器运行）
  │  访问 http://localhost:3333
  ▼
parent-dashboard (Next.js standalone)
  │  浏览器经宿主映射端口调用：NEXT_PUBLIC_API_URL = http://localhost:8310/api/v1
  ▼  （8310 → 容器内 auth-service:8303）
auth-service (Fastify, 内部 8303)
  │  SUPABASE_URL / SUPABASE_KEY
  ▼
Supabase / PostgreSQL
```

- **parent-dashboard**：Next.js `standalone` 产物，容器内跑 `node apps/parent-dashboard/server.js`，端口 `3333`。
- **auth-service**：认证 + 家长 API 代理（7 个端点），源码硬编码监听 `8303`。

> 说明：本仓库唯一 compose 文件是根目录 `docker-compose.yml`。auth-service 此前未容器化，
> 本次一并补了 `Dockerfile`，作为家长控制台的运行依赖。

---

## 2. 涉及文件

| 文件 | 用途 |
|------|------|
| `apps/parent-dashboard/Dockerfile` | 家长控制台镜像（多阶段：pnpm 构建 → standalone 运行） |
| `apps/parent-dashboard/.dockerignore` | 控制台上下文排除项 |
| `apps/parent-dashboard/next.config.js` | 新增 `output: 'standalone'` |
| `services/auth-service/Dockerfile` | 认证服务镜像（自包含 npm 构建） |
| `.dockerignore` | 仓库根上下文排除项（控制台/认证构建 context 是仓库根） |
| `docker-compose.yml` | 新增 `auth-service` + `parent-dashboard` 两个服务 |

---

## 3. 快速启动

```bash
# 只启动家长控制台 + 其认证依赖
docker compose up --build parent-dashboard

# 或连同其他基础服务一起
docker compose up -d --build

# 访问
open http://localhost:3333
```

> 修改 `NEXT_PUBLIC_API_URL` 后必须加 `--build` 重新构建镜像才生效
> （它在 `next build` 时内联进浏览器 bundle，见 [第 4 节](#4-环境变量)）。

查看日志 / 停止：

```bash
docker compose logs -f parent-dashboard auth-service
docker compose down
docker compose down -v   # 连数据卷一起清除
```

单独构建镜像（便于 push 到 registry）：

```bash
docker build -t linguaquest/parent-dashboard:latest -f apps/parent-dashboard/Dockerfile .
docker build -t linguaquest/auth-service:latest    -f services/auth-service/Dockerfile .
```

---

## 4. 环境变量

### 关键：`NEXT_PUBLIC_API_URL` 是**构建期**变量

`NEXT_PUBLIC_*` 会在 `next build` 时**内联进浏览器 bundle**，运行时 `environment:`
对它无效。因此它在 `docker-compose.yml` 中以 **build arg** 传入：

```yaml
parent-dashboard:
  build:
    args:
      NEXT_PUBLIC_API_URL: ${NEXT_PUBLIC_API_URL:-http://localhost:8310/api/v1}
```

因为 API 调用发生在**浏览器侧**（所有页面都是 `'use client'`，`lib/api.ts` 里
`fetch` 都在浏览器执行），所以这个地址必须是**浏览器能访问**的地址：
- 本地开发默认 `http://localhost:8310/api/v1`（浏览器 → 宿主 `8310` → 容器内 `auth-service:8303`）
- 若从其他机器访问，改为宿主可达地址：`http://<宿主机IP>:8310/api/v1`

改了这个值后必须**重新构建镜像**（`docker compose build parent-dashboard`），
只 `docker compose up` 重启容器不会生效。

> 注意：容器名 `auth-service:8303` 只能在**容器网络内部**使用，浏览器访问不到。

其余变量通过根目录 `.env` 覆盖：

```bash
# .env

# 家长控制台调用后端的地址（浏览器侧，默认走宿主映射端口 8310）
NEXT_PUBLIC_API_URL=http://localhost:8310/api/v1

# auth-service 依赖 Supabase（必须提供真实值，否则登录/注册无法命中数据层）
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-service-role-key

# auth-service 代理 summary-service 用（容器内通信，一般保持默认）
SUMMARY_SERVICE_URL=http://summary-service:8303
```

> ⚠️ 默认值仅为占位（`http://postgres:5432` / `dev-key`）。生产/正式联调前
> 务必在 `.env` 中写入真实的 `SUPABASE_URL` 与 `SUPABASE_KEY`（Service Role Key）。

---

## 5. 构建细节

### 5.1 为什么 build context 是仓库根

pnpm monorepo 的 `pnpm install --frozen-lockfile` 要求锁文件里每个 importer 的
`package.json` 都存在（`apps/game-creator`、各 `services/*`、`tests`），所以：

- `parent-dashboard` 的 Dockerfile 使用 **仓库根 context**（`context: .` + `dockerfile: apps/parent-dashboard/Dockerfile`），
  先拷贝全部 importer 的 `package.json` 保证 frozen-lockfile 一致，再只拷贝控制台源码做构建。
- `auth-service` 的 tsconfig `extends: ../../tsconfig.base.json`（仓库根），故同样使用仓库根 context 以取到基配置。

### 5.2 Next.js standalone

`next.config.js` 开启 `output: 'standalone'`，构建产物位于
`apps/parent-dashboard/.next/standalone`。其布局是 monorepo 根定位的：

```
.next/standalone/
├── server.js
├── node_modules/          # 精简依赖
└── apps/parent-dashboard/ # 应用代码 + .next（含 server 等）
```

运行阶段把整个 `standalone` 拷到 `/app`，再单独把 `.next/static` 拷到
`/app/apps/parent-dashboard/.next/static`（静态 JS/CSS 不包含在 standalone 内），
最后 `CMD ["node", "apps/parent-dashboard/server.js"]`。

### 5.3 镜像要点

- 基础镜像 `node:22-alpine`（与仓库 node 版本一致）。
- `NODE_ENV=production`、`PORT=3333`、`HOSTNAME=0.0.0.0`。
- 均带 `HEALTHCHECK`（`wget -qO- http://127.0.0.1:<port>/<health 或 />`）。
- 运行阶段不含构建工具链（pnpm/next），镜像体积精简。

---

## 6. 端口与外部访问

| 服务 | 容器内 | 宿主机 | 说明 |
|------|--------|--------|------|
| parent-dashboard | 3333 | 3333 | Next.js Web |
| auth-service | 8303 | **8310** | 避开 summary-service 已占用的宿主机 8303 |

> auth-service 源码硬编码监听 8303；宿主映射到 8310 是为了避免与
> `summary-service`（`ports: ["8303:8303"]`）在宿主机端口冲突。
>
> **浏览器 → 后端的链路**：浏览器运行在宿主侧 → 访问宿主映射端口 `localhost:8310`
> → Docker 转发到容器内 `auth-service:8303`。因此 `NEXT_PUBLIC_API_URL` 必须写
> `http://localhost:8310/api/v1`（宿主可达），而不是 `auth-service:8303`（仅容器网络内部可达）。
> 其他服务之间的容器内通信（如 `SUMMARY_SERVICE_URL`）才用 `auth-service:8303`。

---

## 7. 常见问题

| 问题 | 原因 | 处理 |
|------|------|------|
| 登录/注册 5xx 或空数据 | Supabase 未正确配置 | 在 `.env` 写真实 `SUPABASE_URL` / `SUPABASE_KEY` 后 `docker compose up -d --build auth-service` |
| 前端调不到后端（如 `ERR_CONNECTION_REFUSED`） | `NEXT_PUBLIC_API_URL` 用了容器名 `auth-service:8303`，浏览器访问不到；或改了值只重启没重建 | 改为**浏览器可达**的宿主映射地址 `http://localhost:8310/api/v1`，并在 docker-compose 的 `build.args` 传入后 `docker compose up --build parent-dashboard` |
| 宿主 8310 未开放仍想直连 8303 | 端口冲突 | 调整 compose 端口映射；容器内地址不受影响 |
| 构建慢 | 仓库根 context 较大 | 已在根 `.dockerignore` 排除 node_modules/.next/.git 等；首次需全量 pnpm 安装 |
| 本地无法构建镜像 | 缺网络拉取 `node:22-alpine` | 先 `docker pull node:22-alpine`，或确保可访问 Docker Hub |
