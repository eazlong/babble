# LinguaQuest RPG

## 项目简介
面向儿童的语言学习 RPG 游戏，采用 CocosCreator 客户端 + AWS 云端微服务 + Supabase 数据存储。

## 当前状态
项目处于文档阶段，尚未开始代码开发。MVP 目标：12 周内交付 Phase 1（第一章完整版，3 场景、5 NPC、英中双语、儿童模式、家长控制台）。

## 技术栈
- **客户端**: CocosCreator 3.8+ (TypeScript)
- **云端核心**: Node.js/Fastify 微服务
- **AI 服务**: Python/FastAPI
- **数据库**: Supabase (PostgreSQL + Auth + Storage)
- **消息队列**: Redis Streams
- **外部服务**: OpenAI API (GPT-4o + Whisper), ElevenLabs TTS
- **家长控制台**: Next.js

## 目录结构
```
ARCHITECTURE.md          # 系统架构设计文档
LinguaQuest_SRS.md       # 软件需求规格说明书
docs/plans/              # 开发计划文档
scripts/                 # 开发辅助脚本
  start-dev-session.sh   # 启动开发会话 (用法: ./scripts/start-dev-session.sh [A|B|C|all])
  prompts/               # 开发轨道 prompt 模板
```

## 开发流程
- **MVP 计划**: `docs/plans/2026-04-16-mvp-implementation.md`
- **开发轨道**: 3 条并行轨道 — A(后端)、B(客户端)、C(家长控制台)
- **子 Agent 使用**: 实施计划时 REQUIRED 使用 `superpowers:executing-plans` subagent

## 语音核心管线
VAD → ASR (Whisper) → LLM (GPT-4o/本地路由) → TTS (ElevenLabs)
精灵教练 Agent 通过 Redis Streams 异步解耦

## MVP 阶段概览
```
阶段 0: 基础设施与项目骨架（Week 1）
阶段 1: 数据库与认证系统（Week 2）
阶段 2: 语音交互管线（Week 3-4）
阶段 3: 对话服务与 NPC 引擎（Week 4-5）
阶段 4: 精灵教练 Agent（Week 5-6）
阶段 5: 任务系统（Week 6-7）
阶段 6: 评估与奖励系统（Week 7-8）
阶段 7: CocosCreator 客户端（Week 4-9）
阶段 8: 儿童模式与家长控制台（Week 9-10）
阶段 9: 集成测试与 MVP 发布（Week 11-12）
```

## Monorepo 工具链
- pnpm workspaces + turborepo
- 预期目录: `packages/server/`, `packages/client/`, `packages/parent-dashboard/`

## 环境依赖
开发需要:
- OpenAI API key (GPT-4o + Whisper)
- ElevenLabs API key (TTS)
- Supabase 项目 + Service Role Key
- Redis 实例
- CocosCreator 3.8+ 已安装
