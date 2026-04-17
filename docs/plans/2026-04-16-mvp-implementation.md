# LinguaQuest RPG MVP 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 交付 Phase 1 MVP — 第一章完整版（3场景、5NPC、英中双语、儿童模式、家长控制台），12周内可运行的语言学习游戏。

**Architecture:** CocosCreator 3.8+ 客户端（TypeScript）+ AWS 云端微服务（Node.js/Fastify 核心服务 + Python/FastAPI AI服务）+ Supabase PostgreSQL 数据存储。语音管线 VAD→ASR→LLM→TTS 为核心链路，精灵教练通过 Redis Streams 异步解耦。

**Tech Stack:** CocosCreator 3.8+ (TypeScript), Node.js/Fastify, Python/FastAPI, Supabase (PostgreSQL+Auth+Storage), Redis Streams, OpenAI API (GPT-4o+Whisper), ElevenLabs TTS, TensorFlow Lite (唤醒词), llama.cpp (本地推理), Kong (API网关), Strapi (CMS), Next.js (家长控制台)

---

## 计划概览

本计划将 MVP 分解为 **9 个阶段、37 个任务组、约 150 个步骤**。每个步骤 2-5 分钟，遵循 TDD 原则，频繁提交。

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
阶段 9: 集成测试与 MVP 发布准备（Week 11-12）
```

---

## 阶段 0：基础设施与项目骨架（Week 1）

### Task 0.1: 项目 Monorepo 初始化

**Files:**
- Create: `package.json`
- Create: `pnpm-workspace.yaml`
- Create: `turbo.json`
- Create: `.gitignore`
- Create: `tsconfig.base.json`

**Step 1: 创建 monorepo 根配置**

```json
// package.json
{
  "name": "linguaquest",
  "private": true,
  "scripts": {
    "dev": "turbo run dev",
    "build": "turbo run build",
    "test": "turbo run test",
    "lint": "turbo run lint"
  },
  "devDependencies": {
    "turbo": "^2.0.0",
    "typescript": "^5.4.0"
  }
}
```

```yaml
# pnpm-workspace.yaml
packages:
  - "packages/*"
  - "services/*"
  - "apps/*"
```

```json
// turbo.json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "dev": { "persistent": true },
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "test": { "dependsOn": ["build"] },
    "lint": {}
  }
}
```

**Step 2: 安装 pnpm 并初始化**

Run: `pnpm install`
Expected: 无报错

**Step 3: 创建基础 TypeScript 配置**

```json
// tsconfig.base.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  }
}
```

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: initialize monorepo with pnpm + turbo"
```


---

### Task 0.2: 云端服务脚手架 — Node.js/Fastify

**Files:**
- Create: `services/dialogue-service/package.json`
- Create: `services/dialogue-service/tsconfig.json`
- Create: `services/dialogue-service/src/index.ts`
- Create: `services/dialogue-service/src/routes/health.ts`
- Test: `services/dialogue-service/src/__tests__/health.test.ts`

**Step 1: 创建 Fastify 服务包配置**

```json
// services/dialogue-service/package.json
{
  "name": "@linguaquest/dialogue-service",
  "version": "0.1.0",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "test": "vitest run",
    "lint": "eslint src/"
  },
  "dependencies": {
    "fastify": "^4.28.0",
    "@fastify/cors": "^9.0.0",
    "@fastify/rate-limit": "^9.0.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "tsx": "^4.7.0",
    "vitest": "^2.0.0",
    "@types/node": "^20.0.0"
  }
}
```

**Step 2: 创建 Fastify 入口文件**

```typescript
// services/dialogue-service/src/index.ts
import Fastify from 'fastify'
import cors from '@fastify/cors'

const app = Fastify({ logger: true })

app.register(cors, { origin: true })

app.get('/health', async () => ({ status: 'ok', service: 'dialogue-service', timestamp: new Date().toISOString() }))

const start = async () => {
  try {
    await app.listen({ port: 8002, host: '0.0.0.0' })
    app.log.info('Dialogue service running on port 8002')
  } catch (err) {
    app.error(err)
    process.exit(1)
  }
}

start()

export default app
```

**Step 3: Write health route test**

```typescript
// services/dialogue-service/src/__tests__/health.test.ts
import { test, expect } from 'vitest'
import app from '../index'

test('GET /health returns ok status', async () => {
  const response = await app.inject({
    method: 'GET',
    url: '/health'
  })
  expect(response.statusCode).toBe(200)
  const body = JSON.parse(response.body)
  expect(body.status).toBe('ok')
  expect(body.service).toBe('dialogue-service')
})
```

**Step 4: Run test to verify it passes**

Run: `cd services/dialogue-service && pnpm test`
Expected: PASS — 1 test passing

**Step 5: Commit**

```bash
git add services/dialogue-service/
git commit -m "feat: scaffold dialogue-service with Fastify + health check"
```

---

### Task 0.3: AI 服务脚手架 — Python/FastAPI

**Files:**
- Create: `services/voice-service/requirements.txt`
- Create: `services/voice-service/src/main.py`
- Create: `services/voice-service/src/api/routes/health.py`
- Test: `services/voice-service/tests/test_health.py`

**Step 1: 创建 Python 包配置**

```
# services/voice-service/requirements.txt
fastapi==0.110.0
uvicorn[standard]==0.29.0
httpx==0.27.0
openai==1.30.0
elevenlabs==1.1.0
python-dotenv==1.0.0
pydantic==2.7.0
# Testing
pytest==8.2.0
pytest-asyncio==0.23.0
httpx==0.27.0
```

**Step 2: 创建 FastAPI 入口**

```python
# services/voice-service/src/main.py
from fastapi import FastAPI
from src.api.routes import health

app = FastAPI(title="LinguaQuest Voice Service", version="0.1.0")
app.include_router(health.router)

@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "voice-service"}
```

```python
# services/voice-service/src/api/routes/health.py
from fastapi import APIRouter

router = APIRouter()

@router.get("/api/v1/health")
async def health():
    return {"status": "ok"}
```

**Step 3: Write test**

```python
# services/voice-service/tests/test_health.py
import pytest
from httpx import AsyncClient, ASGITransport
from src.main import app

@pytest.mark.asyncio
async def test_health_endpoint():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
```

**Step 4: Run test**

Run: `cd services/voice-service && pip install -r requirements.txt && pytest tests/ -v`
Expected: PASS — 1 test

**Step 5: Commit**

```bash
git add services/voice-service/
git commit -m "feat: scaffold voice-service with FastAPI + health check"
```


---

### Task 0.4: CI/CD Pipeline 与 Docker 配置

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `services/dialogue-service/Dockerfile`
- Create: `services/voice-service/Dockerfile`
- Create: `docker-compose.dev.yml`

**Step 1: Create GitHub Actions CI workflow**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service:
          - services/dialogue-service
          - services/voice-service
          - services/spirit-coach-service
          - services/quest-service
          - services/assessment-service
          - services/reward-service

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install pnpm
        uses: pnpm/action-setup@v3
        with:
          version: 9

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Lint
        run: pnpm --filter ${{ matrix.service }} lint

      - name: Type check
        run: pnpm --filter ${{ matrix.service }} exec tsc --noEmit

      - name: Test
        run: pnpm --filter ${{ matrix.service }} test

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        if: matrix.service == 'services/dialogue-service'
```

**Step 2: Create Dockerfile for Node.js services**

```dockerfile
# services/dialogue-service/Dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod
COPY . .
RUN pnpm build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
EXPOSE 8002
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://localhost:8002/health || exit 1
CMD ["node", "dist/index.js"]
```

**Step 3: Create docker-compose for local development**

```yaml
# docker-compose.dev.yml
version: '3.9'
services:
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  postgres:
    image: supabase/postgres:16
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: linguaquest
    ports: ["5432:5432"]
    volumes:
      - pgdata:/var/lib/postgresql/data

  dialogue-service:
    build: ./services/dialogue-service
    ports: ["8002:8002"]
    environment:
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/linguaquest
      REDIS_URL: redis://redis:6379
    depends_on: [postgres, redis]

  voice-service:
    build: ./services/voice-service
    ports: ["8001:8001"]
    environment:
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      ELEVENLABS_API_KEY: ${ELEVENLABS_API_KEY}
    depends_on: [redis]

volumes:
  pgdata:
```

**Step 4: Commit**

```bash
git add .github/workflows/ services/*/Dockerfile docker-compose.dev.yml
git commit -m "ci: add CI/CD pipeline and Docker dev environment"
```

---

## 阶段 1：数据库与认证系统（Week 2）

### Task 1.1: Supabase 数据库初始化与核心 Schema

**Files:**
- Create: `services/db/migrations/001_create_users.sql`
- Create: `services/db/migrations/002_create_scenes.sql`
- Create: `services/db/migrations/003_create_npc_profiles.sql`
- Create: `services/db/migrations/004_create_quests.sql`
- Create: `services/db/migrations/005_create_game_sessions.sql`
- Create: `services/db/migrations/006_create_dialogue_turns.sql`
- Create: `services/db/migrations/007_create_child_accounts.sql`
- Create: `services/db/migrations/008_create_reward_items.sql`
- Create: `services/db/migrations/009_create_player_rewards.sql`
- Create: `services/db/migrations/010_create_vocabulary_entries.sql`
- Create: `services/db/migrations/011_create_assessment_results.sql`
- Create: `services/db/migrations/012_create_error_profiles.sql`
- Create: `services/db/migrations/013_create_quest_progress.sql`
- Create: `services/db/migrations/014_create_spirit_coach_interventions.sql`
- Create: `services/db/migrations/015_create_reward_showcase.sql`
- Create: `services/db/migrations/016_create_content_audit_logs.sql`
- Create: `services/db/migrations/017_create_llm_interaction_logs.sql`

**Step 1: Create users table migration**

```sql
-- services/db/migrations/001_create_users.sql
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    account_type TEXT NOT NULL CHECK (account_type IN ('standard', 'child', 'parent', 'institution')),
    age_group TEXT NOT NULL CHECK (age_group IN ('child', 'teen', 'adult')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ,
    subscription_status TEXT DEFAULT 'free' CHECK (subscription_status IN ('free', 'premium_monthly', 'premium_annual', 'b2b')),
    preferred_language TEXT NOT NULL,
    target_language TEXT NOT NULL,
    cefr_level TEXT DEFAULT 'A1' CHECK (cefr_level IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2'))
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_account_type ON users(account_type);

-- RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_self_access ON users
    FOR ALL USING (auth.uid() = user_id OR auth.uid() IN (
        SELECT parent_id FROM child_data.child_accounts WHERE child_id = users.user_id
    ));
```

**Step 2: Create scenes table migration**

```sql
-- services/db/migrations/002_create_scenes.sql
CREATE TABLE scenes (
    scene_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scene_name TEXT NOT NULL,
    scene_type TEXT NOT NULL,
    real_world_context TEXT,
    core_language_functions JSONB NOT NULL DEFAULT '[]',
    cefr_unlock_requirement TEXT DEFAULT 'A1' CHECK (cefr_unlock_requirement IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2')),
    visual_assets_ref TEXT,
    ambient_audio_ref TEXT,
    chapter_id TEXT NOT NULL,
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_scenes_chapter ON scenes(chapter_id);
CREATE INDEX idx_scenes_cefr ON scenes(cefr_unlock_requirement);

-- MVP: Seed 3 scenes
INSERT INTO scenes (scene_name, scene_type, real_world_context, core_language_functions, cefr_unlock_requirement, chapter_id) VALUES
('王都集市', 'marketplace', '购物/市场交易', '["描述物品", "询价", "议价", "数量表达"]', 'A1', 'chapter_1'),
('冒险者酒馆', 'tavern', '餐厅/社交场所', '["点餐", "寒暄", "讲故事", "邀约"]', 'A1', 'chapter_1'),
('冒险者公会', 'guild', '机构办事', '["任务描述", "方向表达", "指令理解"]', 'A1', 'chapter_1');
```

**Step 3: Create remaining migrations (NPC, Quests, Sessions, etc.)**

See architecture doc section 4.2 for full DDL. Each migration file follows the same pattern:
- CREATE TABLE with constraints
- CREATE INDEX for query patterns
- ALTER TABLE ENABLE ROW LEVEL SECURITY
- CREATE POLICY for access control

**Step 4: Run all migrations**

Run: `cd services/db && npx supabase db push`
Expected: 17 migrations applied, 0 errors

**Step 5: Commit**

```bash
git add services/db/migrations/
git commit -m "feat: create 17 database migrations for MVP schema with RLS policies"
```


---

### Task 1.2: Supabase Auth 与用户注册 API

**Files:**
- Create: `services/auth-service/package.json`
- Create: `services/auth-service/src/index.ts`
- Create: `services/auth-service/src/routes/register.ts`
- Create: `services/auth-service/src/routes/login.ts`
- Create: `services/auth-service/src/middleware/auth.ts`
- Test: `services/auth-service/src/__tests__/register.test.ts`

**Step 1: Create auth service**

```typescript
// services/auth-service/src/routes/register.ts
import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  display_name: z.string().min(1).max(50),
  preferred_language: z.string().default('en'),
  target_language: z.string().default('en')
})

export async function registerRoutes(app: FastifyInstance) {
  app.post('/api/v1/auth/register', {
    schema: {
      body: registerSchema,
      response: {
        201: {
          type: 'object',
          properties: {
            user_id: { type: 'string' },
            email: { type: 'string' },
            display_name: { type: 'string' }
          }
        }
      }
    }
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const { email, password, display_name, preferred_language, target_language } = registerSchema.parse(request.body)

    // Supabase Auth signup
    const { data, error } = await app.supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          display_name,
          preferred_language,
          target_language
        }
      }
    })

    if (error) {
      return reply.status(400).send({ error: { code: 'REGISTER_FAILED', message: error.message } })
    }

    // Create user record in public.users table
    await app.supabase.from('users').insert({
      user_id: data.user!.id,
      email,
      display_name,
      account_type: 'standard',
      age_group: 'adult',
      preferred_language,
      target_language,
      subscription_status: 'free'
    })

    return reply.status(201).send({
      user_id: data.user!.id,
      email: data.user!.email!,
      display_name
    })
  })
}
```

**Step 2: Write test**

```typescript
// services/auth-service/src/__tests__/register.test.ts
import { test, expect, vi } from 'vitest'

test('POST /api/v1/auth/register creates user account', async () => {
  // Mock Supabase auth
  const mockSignUp = vi.fn().mockResolvedValue({
    data: { user: { id: 'test-uuid', email: 'test@example.com' } },
    error: null
  })

  // ... test implementation
  expect(mockSignUp).toHaveBeenCalledWith({
    email: 'test@example.com',
    password: 'password123',
    options: expect.any(Object)
  })
})
```

**Step 3: Commit**

```bash
git add services/auth-service/
git commit -m "feat: add auth-service with register/login endpoints and Supabase Auth integration"
```

---

## 阶段 2：语音交互管线（Week 3-4）

### Task 2.1: ASR 处理器（Whisper API 集成）

**Files:**
- Modify: `services/voice-service/src/main.py`
- Create: `services/voice-service/src/api/routes/asr.py`
- Create: `services/voice-service/src/services/whisper.py`
- Test: `services/voice-service/tests/test_asr.py`

**Step 1: Create Whisper service wrapper**

```python
# services/voice-service/src/services/whisper.py
import os
from openai import AsyncOpenAI
from dataclasses import dataclass

@dataclass
class ASRResult:
    text: str
    confidence: float
    language: str

class WhisperService:
    def __init__(self):
        self.client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"])

    async def transcribe(self, audio_bytes: bytes, language: str = "en") -> ASRResult:
        """Transcribe audio bytes to text using Whisper API."""
        import io
        audio_file = io.BytesIO(audio_bytes)
        audio_file.name = "audio.wav"

        response = await self.client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
            language=language,
            response_format="verbose_json"
        )

        return ASRResult(
            text=response.text,
            confidence=1.0 - (getattr(response, 'word_confidence', [0.9])[0] if hasattr(response, 'word_confidence') else 0.1),
            language=language
        )

whisper_service = WhisperService()
```

**Step 2: Create ASR route**

```python
# services/voice-service/src/api/routes/asr.py
from fastapi import APIRouter, UploadFile, File, Form
from src.services.whisper import whisper_service

router = APIRouter()

@router.post("/api/v1/voice/asr")
async def transcribe(
    audio: UploadFile = File(...),
    language: str = Form(default="en")
):
    audio_bytes = await audio.read()
    result = await whisper_service.transcribe(audio_bytes, language)
    return {
        "text": result.text,
        "confidence": result.confidence,
        "language": result.language
    }
```

**Step 3: Write test**

```python
# services/voice-service/tests/test_asr.py
import pytest
from unittest.mock import patch, AsyncMock
from httpx import AsyncClient, ASGITransport
from src.main import app
from src.services.whisper import ASRResult

@pytest.mark.asyncio
async def test_asr_endpoint():
    with patch('src.api.routes.asr.whisper_service.transcribe', new_callable=AsyncMock) as mock_transcribe:
        mock_transcribe.return_value = ASRResult(text="Hello world", confidence=0.95, language="en")

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/voice/asr",
                files={"audio": ("test.wav", b"fake-audio-data", "audio/wav")},
                data={"language": "en"}
            )

        assert response.status_code == 200
        data = response.json()
        assert data["text"] == "Hello world"
        assert data["confidence"] == 0.95
```

**Step 4: Run test**

Run: `cd services/voice-service && pytest tests/test_asr.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add services/voice-service/
git commit -m "feat: add ASR endpoint with Whisper API integration"
```

---

### Task 2.2: TTS 合成器（ElevenLabs 集成）

**Files:**
- Create: `services/voice-service/src/services/elevenlabs.py`
- Create: `services/voice-service/src/api/routes/tts.py`
- Test: `services/voice-service/tests/test_tts.py`

**Step 1: Create ElevenLabs service**

```python
# services/voice-service/src/services/elevenlabs.py
import os
from elevenlabs import ElevenLabs, VoiceSettings
from dataclasses import dataclass

@dataclass
class TTSResult:
    audio_url: str
    duration_ms: int

class ElevenLabsService:
    def __init__(self):
        self.client = ElevenLabs(api_key=os.environ["ELEVENLABS_API_KEY"])
        # MVP: 5 basic NPC voices
        self.voice_map = {
            "scholar": "scholar_voice_id",
            "merchant": "merchant_voice_id",
            "storyteller": "storyteller_voice_id",
            "receptionist": "receptionist_voice_id",
            "street_child": "street_child_voice_id",
            "spirit": "spirit_voice_id"
        }

    async def synthesize(self, text: str, voice_id: str = "spirit") -> TTSResult:
        """Synthesize text to audio using ElevenLabs."""
        audio = self.client.generate(
            text=text,
            voice=self.voice_map.get(voice_id, voice_id),
            model="eleven_turbo_v2_5"
        )

        # Upload to Supabase Storage and return URL
        import uuid
        audio_ref = f"tts/{uuid.uuid4()}.mp3"
        # Store in Supabase Storage...

        return TTSResult(audio_url=audio_ref, duration_ms=len(text) * 50)

elevenlabs_service = ElevenLabsService()
```

**Step 2: Create TTS route**

```python
# services/voice-service/src/api/routes/tts.py
from fastapi import APIRouter
from pydantic import BaseModel
from src.services.elevenlabs import elevenlabs_service

router = APIRouter()

class TTSRequest(BaseModel):
    text: str
    voice_id: str = "spirit"
    language: str = "en"

@router.post("/api/v1/voice/tts")
async def synthesize_speech(req: TTSRequest):
    result = await elevenlabs_service.synthesize(req.text, req.voice_id)
    return {"audio_url": result.audio_url, "duration_ms": result.duration_ms}
```

**Step 3: Commit**

```bash
git add services/voice-service/src/api/routes/tts.py services/voice-service/src/services/elevenlabs.py
git commit -m "feat: add TTS endpoint with ElevenLabs integration"
```


---

### Task 2.3: LLM 路由中间件（云端/本地智能路由）

**Files:**
- Modify: `services/dialogue-service/src/index.ts`
- Create: `services/dialogue-service/src/services/llm-router.ts`
- Create: `services/dialogue-service/src/services/openai.ts`
- Create: `services/dialogue-service/src/services/anthropic.ts`
- Test: `services/dialogue-service/src/__tests__/llm-router.test.ts`

**Step 1: Create LLM router with smart routing**

```typescript
// services/dialogue-service/src/services/llm-router.ts
import OpenAI from 'openai'
import Anthropic from '@anthropic-ai/sdk'

export type TaskType = 'npc_dialogue' | 'vocabulary_explain' | 'pronunciation_demo' | 'coach_analysis' | 'quest_narration'

export interface LLMResponse {
  text: string
  model_used: string
  deployment_mode: 'cloud' | 'local'
  prompt_tokens: number
  completion_tokens: number
  latency_ms: number
}

export class LLMRouter {
  private openai: OpenAI
  private anthropic: Anthropic
  private fallbackOpenAI: OpenAI

  constructor() {
    this.openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
    this.anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY })
    this.fallbackOpenAI = new OpenAI({ apiKey: process.env.OPENAI_API_KEY_BACKUP })
  }

  private isSimpleTask(taskType: TaskType): boolean {
    return taskType === 'vocabulary_explain' || taskType === 'pronunciation_demo'
  }

  async generate(prompt: string, taskType: TaskType, maxTokens: number = 200): Promise<LLMResponse> {
    const startTime = Date.now()

    try {
      if (this.isSimpleTask(taskType)) {
        // Route to GPT-4o-mini for simple tasks (cost optimization)
        return await this.callGPT4oMini(prompt, maxTokens, startTime, taskType)
      }

      // Route to GPT-4o for complex tasks
      return await this.callGPT4o(prompt, maxTokens, startTime, taskType)
    } catch (primaryError) {
      console.error('Primary LLM failed, trying fallback:', primaryError)
      try {
        return await this.callClaude(prompt, maxTokens, startTime, taskType)
      } catch (claudeError) {
        console.error('Fallback LLM also failed:', claudeError)
        throw new Error('All LLM providers failed')
      }
    }
  }

  private async callGPT4o(prompt: string, maxTokens: number, startTime: number, taskType: TaskType): Promise<LLMResponse> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: maxTokens,
      temperature: 0.7
    })

    return {
      text: response.choices[0].message.content || '',
      model_used: 'gpt-4o',
      deployment_mode: 'cloud',
      prompt_tokens: response.usage?.prompt_tokens || 0,
      completion_tokens: response.usage?.completion_tokens || 0,
      latency_ms: Date.now() - startTime
    }
  }

  private async callGPT4oMini(prompt: string, maxTokens: number, startTime: number, taskType: TaskType): Promise<LLMResponse> {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: maxTokens,
      temperature: 0.5
    })

    return {
      text: response.choices[0].message.content || '',
      model_used: 'gpt-4o-mini',
      deployment_mode: 'cloud',
      prompt_tokens: response.usage?.prompt_tokens || 0,
      completion_tokens: response.usage?.completion_tokens || 0,
      latency_ms: Date.now() - startTime
    }
  }

  private async callClaude(prompt: string, maxTokens: number, startTime: number, taskType: TaskType): Promise<LLMResponse> {
    const response = await this.anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: maxTokens,
      messages: [{ role: 'user', content: prompt }]
    })

    return {
      text: response.content[0].type === 'text' ? response.content[0].text : '',
      model_used: 'claude-sonnet-4',
      deployment_mode: 'cloud',
      prompt_tokens: response.usage?.input_tokens || 0,
      completion_tokens: response.usage?.output_tokens || 0,
      latency_ms: Date.now() - startTime
    }
  }
}
```

**Step 2: Write test**

```typescript
// services/dialogue-service/src/__tests__/llm-router.test.ts
import { test, expect, vi, beforeEach } from 'vitest'
import { LLMRouter, TaskType } from '../services/llm-router'

test('simple tasks route to GPT-4o-mini', async () => {
  const router = new LLMRouter()
  // Mock internal methods
  vi.spyOn(router as any, 'callGPT4oMini').mockResolvedValue({
    text: 'Hello',
    model_used: 'gpt-4o-mini',
    deployment_mode: 'cloud',
    prompt_tokens: 10,
    completion_tokens: 5,
    latency_ms: 200
  })

  const result = await router.generate('Explain the word "run"', 'vocabulary_explain')
  expect(result.model_used).toBe('gpt-4o-mini')
})

test('complex tasks route to GPT-4o', async () => {
  const router = new LLMRouter()
  vi.spyOn(router as any, 'callGPT4o').mockResolvedValue({
    text: 'Welcome to the tavern...',
    model_used: 'gpt-4o',
    deployment_mode: 'cloud',
    prompt_tokens: 500,
    completion_tokens: 200,
    latency_ms: 600
  })

  const result = await router.generate('You are a tavern keeper...', 'npc_dialogue')
  expect(result.model_used).toBe('gpt-4o')
})
```

**Step 3: Commit**

```bash
git add services/dialogue-service/src/services/llm-router.ts services/dialogue-service/src/__tests__/llm-router.test.ts
git commit -m "feat: add LLM router with smart routing (GPT-4o/GPT-4o-mini/Claude)"
```

---

### Task 2.4: 内容安全过滤服务

**Files:**
- Create: `services/content-filter-service/package.json`
- Create: `services/content-filter-service/src/index.ts`
- Create: `services/content-filter-service/src/services/moderation.ts`
- Test: `services/content-filter-service/src/__tests__/moderation.test.ts`

**Step 1: Create content filter service**

```typescript
// services/content-filter-service/src/services/moderation.ts
import OpenAI from 'openai'

export interface ModerationResult {
  safe: boolean
  categories: Record<string, boolean>
  flagged_categories: string[]
}

export class ContentFilter {
  private openai: OpenAI
  private blockedPatterns: RegExp[]

  constructor() {
    this.openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
    this.blockedPatterns = [
      // Child-specific safety patterns
      /(?:kill|die|death|hurt)/i,
      /(?:blood|weapon|fight)/i,
    ]
  }

  async check(text: string, isChildMode: boolean = false): Promise<ModerationResult> {
    // Layer 1: OpenAI Moderation API
    const modResponse = await this.openai.moderations.create({
      input: text,
      model: 'text-moderation-latest'
    })

    const result = modResponse.results[0]
    const flaggedCategories = Object.entries(result.categories)
      .filter(([_, flagged]) => flagged)
      .map(([category]) => category)

    // Layer 2: Custom rule engine
    if (isChildMode) {
      for (const pattern of this.blockedPatterns) {
        if (pattern.test(text)) {
          flaggedCategories.push('child_unsafe')
        }
      }
    }

    return {
      safe: flaggedCategories.length === 0,
      categories: result.categories,
      flagged_categories: flaggedCategories
    }
  }
}
```

**Step 2: Commit**

```bash
git add services/content-filter-service/
git commit -m "feat: add content filter service with dual-layer safety (OpenAI Moderation + custom rules)"
```


---

## 阶段 3：对话服务与 NPC 引擎（Week 4-5）

### Task 3.1: NPC 对话引擎

**Files:**
- Create: `services/dialogue-service/src/services/npc-engine.ts`
- Create: `services/dialogue-service/src/services/prompt-manager.ts`
- Create: `services/dialogue-service/src/routes/dialogue.ts`
- Test: `services/dialogue-service/src/__tests__/npc-engine.test.ts`

**Step 1: Create prompt manager**

```typescript
// services/dialogue-service/src/services/prompt-manager.ts
export interface NPCProfile {
  name: string
  npc_type: string
  language_style: string
  formality: 'formal' | 'informal' | 'mixed'
  vocabulary_level: 'basic' | 'intermediate' | 'advanced'
  personality: string
}

export class PromptManager {
  static buildNPCSystemPrompt(npc: NPCProfile, playerCefrLevel: string): string {
    return `你是 "${npc.name}"，一个${npc.npc_type}。
语言风格：${npc.language_style}
正式程度：${npc.formality}
词汇等级：${npc.vocabulary_level}（对应用户 CEFR ${playerCefrLevel}）
性格：${npc.personality}

规则：
1. 始终保持在角色中
2. 根据玩家的 CEFR 等级调整词汇和句式复杂度
3. 当玩家语法错误时，以角色身份自然引导重新表达，不要直接指出错误
4. 每次回复控制在 3 句话以内
5. 使用目标语言回复（玩家母语仅用于引导）
6. 不要生成任何暴力、色情或不当内容`
  }

  static buildDialogueContext(history: Array<{speaker: string, text: string}>): string {
    if (history.length === 0) return ''
    const recent = history.slice(-4)
    return recent.map(h => `${h.speaker}: ${h.text}`).join('\n')
  }
}
```

**Step 2: Create NPC engine**

```typescript
// services/dialogue-service/src/services/npc-engine.ts
import { LLMRouter, LLMResponse } from './llm-router'
import { PromptManager, NPCProfile } from './prompt-manager'
import { ContentFilter } from '../../content-filter-service/src/services/moderation'

export interface DialogueRequest {
  user_id: string
  npc_id: string
  player_input: string
  session_id: string
  language: string
  cefr_level: string
  quest_context?: string
}

export interface DialogueResponse {
  npc_text: string
  audio_url: string
  lxp_earned: number
  flagged: boolean
}

export class NPCEngine {
  private llmRouter: LLMRouter
  private contentFilter: ContentFilter

  constructor() {
    this.llmRouter = new LLMRouter()
    this.contentFilter = new ContentFilter()
  }

  async processDialogue(request: DialogueRequest, npc: NPCProfile, history: Array<{speaker: string, text: string}>): Promise<DialogueResponse> {
    const systemPrompt = PromptManager.buildNPCSystemPrompt(npc, request.cefr_level)
    const context = PromptManager.buildDialogueContext(history)

    const userPrompt = context
      ? `${context}\n\nPlayer: ${request.player_input}\n\nRespond as ${npc.name}:`
      : `Player: ${request.player_input}\n\nRespond as ${npc.name}:`

    const fullPrompt = quest_context
      ? `${userPrompt}\n\n[Current quest: ${quest_context}]`
      : userPrompt

    // Call LLM
    const llmResponse = await this.llmRouter.generate(
      `${systemPrompt}\n\n${fullPrompt}`,
      'npc_dialogue',
      300
    )

    // Content safety check
    const moderation = await this.contentFilter.check(llmResponse.text)

    if (!moderation.safe) {
      // Fallback to safe response
      return {
        npc_text: 'I am not sure how to respond to that. Let us continue our conversation.',
        audio_url: '',
        lxp_earned: 0,
        flagged: true
      }
    }

    return {
      npc_text: llmResponse.text,
      audio_url: '', // TTS will be called separately
      lxp_earned: this.calculateLXP(request.player_input, llmResponse.text),
      flagged: false
    }
  }

  private calculateLXP(playerInput: string, npcResponse: string): number {
    // Simplified LXP: based on input length and response engagement
    const words = playerInput.split(/\s+/).length
    return Math.min(100, Math.max(10, words * 5))
  }
}
```

**Step 3: Create dialogue route**

```typescript
// services/dialogue-service/src/routes/dialogue.ts
import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { NPCEngine } from '../services/npc-engine'

const dialogueSchema = z.object({
  npc_id: z.string(),
  player_input: z.string().min(1).max(500),
  session_id: z.string(),
  language: z.string().default('en')
})

export async function registerDialogueRoutes(app: FastifyInstance) {
  const npcEngine = new NPCEngine()

  app.post('/api/v1/dialogue', async (request, reply) => {
    const body = dialogueSchema.parse(request.body)

    // Fetch NPC profile from DB
    const { data: npc, error } = await app.supabase
      .from('npc_profiles')
      .select('*')
      .eq('npc_id', body.npc_id)
      .single()

    if (error || !npc) {
      return reply.status(404).send({ error: { code: 'NPC_NOT_FOUND' } })
    }

    // Fetch dialogue history
    const { data: history } = await app.supabase
      .from('dialogue_turns')
      .select('speaker_type, asr_text, npc_response_text')
      .eq('session_id', body.session_id)
      .order('turn_number', { ascending: true })
      .limit(10)

    const result = await npcEngine.processDialogue(
      { ...body, user_id: request.user_id, cefr_level: 'A1' },
      npc.language_style_profile,
      history || []
    )

    return reply.send(result)
  })
}
```

**Step 4: Commit**

```bash
git add services/dialogue-service/src/services/npc-engine.ts services/dialogue-service/src/services/prompt-manager.ts services/dialogue-service/src/routes/dialogue.ts
git commit -m "feat: add NPC dialogue engine with prompt management and content safety"
```

---

## 阶段 4：精灵教练 Agent（Week 5-6）

### Task 4.1: 错误检测与干预系统

**Files:**
- Create: `services/spirit-coach-service/package.json`
- Create: `services/spirit-coach-service/src/index.ts`
- Create: `services/spirit-coach-service/src/services/error-detector.ts`
- Create: `services/spirit-coach-service/src/services/intervention-manager.ts`
- Create: `services/spirit-coach-service/src/routes/coach.ts`
- Create: `services/spirit-coach-service/src/workers/message-consumer.ts`
- Test: `services/spirit-coach-service/src/__tests__/error-detector.test.ts`

**Step 1: Create error detector**

```typescript
// services/spirit-coach-service/src/services/error-detector.ts
import { LLMRouter, LLMResponse } from '../../dialogue-service/src/services/llm-router'

export type ErrorType = 'grammar' | 'vocabulary' | 'pronunciation' | 'pragmatic'
export type Severity = 'low' | 'medium' | 'high'

export interface DetectedError {
  type: ErrorType
  severity: Severity
  original_text: string
  correction: string
  explanation: string
}

export class ErrorDetector {
  private llmRouter: LLMRouter

  constructor() {
    this.llmRouter = new LLMRouter()
  }

  async analyze(playerInput: string, expectedLevel: string = 'A1'): Promise<DetectedError[]> {
    const prompt = `Analyze the following language input for errors. Focus on grammar and vocabulary errors only.

Player input: "${playerInput}"
Expected CEFR level: ${expectedLevel}

Rules:
1. Only flag HIGH severity errors (completely wrong tense, wrong word choice that changes meaning)
2. Do NOT flag minor accent variations or common learner errors that don't impede communication
3. For each error, provide: type, severity, correction, and a brief encouraging explanation
4. If no errors found, return empty array

Respond in JSON format:
[{"type": "grammar|vocabulary", "severity": "high", "original_text": "...", "correction": "...", "explanation": "..."}]`

    const response = await this.llmRouter.generate(prompt, 'coach_analysis', 500)

    try {
      return JSON.parse(response.text) as DetectedError[]
    } catch {
      return []
    }
  }
}
```

**Step 2: Create Redis message consumer**

```typescript
// services/spirit-coach-service/src/workers/message-consumer.ts
import Redis from 'ioredis'
import { ErrorDetector, DetectedError } from '../services/error-detector'
import { createClient } from '@supabase/supabase-js'

export class MessageConsumer {
  private redis: Redis
  private errorDetector: ErrorDetector
  private supabase

  constructor(redisUrl: string, supabaseUrl: string, supabaseKey: string) {
    this.redis = new Redis(redisUrl)
    this.errorDetector = new ErrorDetector()
    this.supabase = createClient(supabaseUrl, supabaseKey)
  }

  async start(): Promise<void> {
    console.log('Spirit coach message consumer started')

    while (true) {
      try {
        const result = await this.redis.xread(
          'BLOCK', 5000,
          'STREAMS',
          'spirit_coach_queue',
          '0'
        )

        if (!result) continue

        for (const [stream, messages] of result) {
          for (const [messageId, data] of messages) {
            await this.processMessage(data)
            await this.redis.xdel('spirit_coach_queue', messageId)
          }
        }
      } catch (error) {
        console.error('Message consumer error:', error)
        await new Promise(resolve => setTimeout(resolve, 1000))
      }
    }
  }

  private async processMessage(data: Record<string, string>): Promise<void> {
    const { turn_id, session_id, asr_text, user_id } = data

    // Analyze for errors
    const errors = await this.errorDetector.analyze(asr_text)

    // Only store high-severity errors
    const highErrors = errors.filter(e => e.severity === 'high')

    for (const error of highErrors) {
      // Save intervention record
      await this.supabase.from('spirit_coach_interventions').insert({
        turn_id,
        session_id,
        error_type: error.type,
        severity: error.severity,
        coach_suggestion_text: error.explanation,
        player_adopted: false,
        intervention_timing_ms: 0
      })

      // Push notification to client via Supabase Realtime
      await this.supabase.channel(`coach:${user_id}`).send({
        type: 'broadcast',
        event: 'coach_hint',
        payload: { error, hint: error.explanation }
      })
    }
  }
}
```

**Step 3: Commit**

```bash
git add services/spirit-coach-service/
git commit -m "feat: add spirit coach service with error detection and Redis message consumer"
```


---

## 阶段 5：任务系统（Week 6-7）

### Task 5.1: 任务引擎与进度追踪

**Files:**
- Create: `services/quest-service/package.json`
- Create: `services/quest-service/src/index.ts`
- Create: `services/quest-service/src/services/quest-engine.ts`
- Create: `services/quest-service/src/routes/quests.ts`
- Create: `services/quest-service/src/routes/daily-quests.ts`
- Test: `services/quest-service/src/__tests__/quest-engine.test.ts`

**Step 1: Create quest engine**

```typescript
// services/quest-service/src/services/quest-engine.ts
import { createClient } from '@supabase/supabase-js'

export interface QuestCompletionResult {
  success: boolean
  lxp_earned: number
  accuracy_score: number
  fluency_score: number
  vocabulary_score: number
  rewards: Array<{ item_id: string; name: string }>
}

export class QuestEngine {
  private supabase

  constructor(supabaseUrl: string, supabaseKey: string) {
    this.supabase = createClient(supabaseUrl, supabaseKey)
  }

  async getUserQuests(userId: string, sceneId?: string): Promise<any[]> {
    let query = this.supabase
      .from('quests')
      .select(`
        *,
        quest_progress!inner(*)
      `)
      .eq('quest_progress.user_id', userId)

    if (sceneId) {
      query = query.eq('scene_id', sceneId)
    }

    const { data, error } = await query
    if (error) throw error
    return data
  }

  async completeQuest(
    userId: string,
    questId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number }
  ): Promise<QuestCompletionResult> {
    // Calculate LXP: accuracy × 0.4 + fluency × 0.3 + vocabulary × 0.3
    const lxp = Math.round(
      scores.accuracy * 0.4 +
      scores.fluency * 0.3 +
      scores.vocabulary * 0.3
    )

    // Update quest progress
    await this.supabase
      .from('quest_progress')
      .update({
        status: 'completed',
        completed_at: new Date().toISOString(),
        accuracy_score: scores.accuracy,
        fluency_score: scores.fluency,
        vocabulary_score: scores.vocabulary
      })
      .eq('user_id', userId)
      .eq('quest_id', questId)

    // Award LXP to game session
    await this.supabase
      .from('game_sessions')
      .update({ lxp_earned: this.supabase.raw('lxp_earned + ' + lxp) })
      .eq('user_id', userId)
      .is('end_time', null)

    // Check for reward drops
    const rewards = await this.calculateRewards(userId, questId)

    return {
      success: true,
      lxp_earned: lxp,
      ...scores,
      rewards
    }
  }

  private async calculateRewards(userId: string, questId: string): Promise<Array<{ item_id: string; name: string }>> {
    // Get quest info for reward calculation
    const { data: quest } = await this.supabase
      .from('quests')
      .select('quest_type, difficulty_level')
      .eq('quest_id', questId)
      .single()

    if (!quest) return []

    // Determine rarity based on quest type
    const rarity = quest.quest_type === 'main' ? 'epic' : 'rare'

    // Roll for reward
    const roll = Math.random() * 100
    let dropChance = 0

    if (rarity === 'epic') dropChance = 80
    else if (rarity === 'rare') dropChance = 50

    if (roll <= dropChance) {
      const { data: item } = await this.supabase
        .from('reward_items')
        .select('item_id, name')
        .eq('rarity', rarity)
        .order(this.supabase.raw('RANDOM()'))
        .limit(1)
        .single()

      if (item) {
        // Grant reward to player
        await this.supabase.from('player_rewards').insert({
          user_id: userId,
          item_id: item.item_id,
          source_type: `quest_${quest.quest_type}`,
          source_id: questId,
          is_equipped: false
        })

        return [item]
      }
    }

    return []
  }

  async generateDailyQuests(userId: string): Promise<any[]> {
    // Check if dailies already generated today
    const today = new Date().toISOString().split('T')[0]
    const { data: existing } = await this.supabase
      .from('quest_progress')
      .select('started_at')
      .eq('user_id', userId)
      .eq('status', 'available')

    if (existing && existing.length > 0) {
      const startDate = existing[0].started_at.split('T')[0]
      if (startDate === today) {
        // Return existing dailies
        return existing
      }
    }

    // Generate 3 new daily quests matching user CEFR level
    const { data: user } = await this.supabase
      .from('users')
      .select('cefr_level')
      .eq('user_id', userId)
      .single()

    const { data: availableQuests } = await this.supabase
      .from('quests')
      .select('*')
      .eq('quest_type', 'daily')
      .eq('cefr_requirement', user?.cefr_level || 'A1')
      .order(this.supabase.raw('RANDOM()'))
      .limit(3)

    if (!availableQuests || availableQuests.length < 3) {
      // Not enough dailies, use fallback
      return this.getFallbackDailies(userId)
    }

    // Create progress records
    for (const quest of availableQuests) {
      await this.supabase.from('quest_progress').insert({
        quest_id: quest.quest_id,
        user_id: userId,
        status: 'available',
        started_at: new Date().toISOString()
      })
    }

    return availableQuests
  }

  private async getFallbackDailies(userId: string): Promise<any[]> {
    // Hardcoded fallback daily quests
    const fallbacks = [
      { quest_id: 'daily_greet', title: '用目标语言向3个人打招呼', target_language_focus: ['greeting'] },
      { quest_id: 'daily_shop', title: '在集市购买一件物品并用目标语言询价', target_language_focus: ['shopping', 'numbers'] },
      { quest_id: 'daily_directions', title: '询问并理解一个地点的方向', target_language_focus: ['directions', 'locations'] }
    ]

    return fallbacks.map(q => ({
      ...q,
      quest_type: 'daily',
      lxp_reward_base: 20,
      cefr_requirement: 'A1'
    }))
  }
}
```

**Step 2: Commit**

```bash
git add services/quest-service/
git commit -m "feat: add quest service with engine, progress tracking, and daily quest generation"
```

---

## 阶段 6：评估与奖励系统（Week 7-8）

### Task 6.1: 微评估服务（3维雷达图）

**Files:**
- Create: `services/assessment-service/requirements.txt`
- Create: `services/assessment-service/src/main.py`
- Create: `services/assessment-service/src/api/routes/assessment.py`
- Create: `services/assessment-service/src/services/micro_assessment.py`
- Test: `services/assessment-service/tests/test_assessment.py`

**Step 1: Create micro assessment service**

```python
# services/assessment-service/src/services/micro_assessment.py
from dataclasses import dataclass
from typing import List, Dict
import math

@dataclass
class AssessmentScores:
    accuracy: float  # 0-100
    fluency: float   # 0-100
    vocabulary: float  # 0-100

    def to_dict(self) -> Dict[str, float]:
        return {
            "accuracy": round(self.accuracy, 1),
            "fluency": round(self.fluency, 1),
            "vocabulary": round(self.vocabulary, 1)
        }

    def radar_chart_data(self) -> List[Dict]:
        return [
            {"axis": "Accuracy", "value": self.accuracy},
            {"axis": "Fluency", "value": self.fluency},
            {"axis": "Vocabulary", "value": self.vocabulary}
        ]

class MicroAssessmentService:
    def calculate(self,
                  dialogue_turns: List[Dict],
                  asr_confidence_scores: List[float],
                  response_times_ms: List[int]) -> AssessmentScores:
        """Calculate 3D assessment scores from a quest completion."""

        if not dialogue_turns:
            return AssessmentScores(0, 0, 0)

        # Accuracy: based on ASR confidence (proxy for clear pronunciation)
        avg_confidence = sum(asr_confidence_scores) / len(asr_confidence_scores)
        accuracy = min(100, avg_confidence * 100)

        # Fluency: based on response time (faster = more fluent)
        avg_response_time = sum(response_times_ms) / len(response_times_ms)
        # Ideal: < 2000ms, Poor: > 5000ms
        fluency = max(0, min(100, 100 - (avg_response_time - 2000) / 30))

        # Vocabulary: based on unique word count
        all_words = []
        for turn in dialogue_turns:
            words = turn.get('asr_text', '').split()
            all_words.extend(w.lower() for w in words)

        unique_words = len(set(all_words))
        total_words = len(all_words)
        ttr = unique_words / max(1, total_words)  # Type-Token Ratio
        vocabulary = min(100, ttr * 150)  # Scale TTR to 0-100

        return AssessmentScores(accuracy, fluency, vocabulary)
```

**Step 2: Create assessment route**

```python
# services/assessment-service/src/api/routes/assessment.py
from fastapi import APIRouter
from pydantic import BaseModel
from src.services.micro_assessment import MicroAssessmentService

router = APIRouter()

class AssessmentRequest(BaseModel):
    user_id: str
    session_id: str
    quest_id: str
    dialogue_turns: list
    asr_confidence_scores: list
    response_times_ms: list

@router.post("/api/v1/assessment/micro")
async def calculate_micro_assessment(req: AssessmentRequest):
    service = MicroAssessmentService()
    scores = service.calculate(
        req.dialogue_turns,
        req.asr_confidence_scores,
        req.response_times_ms
    )

    return {
        "scores": scores.to_dict(),
        "radar_chart": scores.radar_chart_data()
    }
```

**Step 3: Commit**

```bash
git add services/assessment-service/
git commit -m "feat: add assessment service with 3D micro assessment (accuracy/fluency/vocabulary)"
```

---

### Task 6.2: 奖励服务（掉落引擎 + 展示厅）

**Files:**
- Create: `services/reward-service/package.json`
- Create: `services/reward-service/src/index.ts`
- Create: `services/reward-service/src/services/drop-engine.ts`
- Create: `services/reward-service/src/routes/rewards.ts`
- Test: `services/reward-service/src/__tests__/drop-engine.test.ts`

**Step 1: Create drop engine**

```typescript
// services/reward-service/src/services/drop-engine.ts
export type Rarity = 'common' | 'rare' | 'epic' | 'legendary' | 'limited'
export type ItemType = 'skin_protagonist' | 'skin_spirit' | 'decoration' | 'title' | 'effect'

export interface DropResult {
  item_id: string
  name: string
  item_type: ItemType
  rarity: Rarity
  thumbnail_ref: string
}

export class DropEngine {
  // Rarity drop rates from SRS
  private dropRates: Record<Rarity, number> = {
    common: 70,
    rare: 20,
    epic: 8,
    legendary: 2,
    limited: 0  // Event only
  }

  rollRarity(questType: 'main' | 'side' | 'daily'): Rarity {
    const roll = Math.random() * 100

    // Main quests have better drop rates
    if (questType === 'main') {
      if (roll < 2) return 'legendary'
      if (roll < 10) return 'epic'
      if (roll < 30) return 'rare'
      return 'common'
    }

    if (roll < 2) return 'epic'
    if (roll < 22) return 'rare'
    return 'common'
  }

  async calculateDrop(
    userId: string,
    questType: 'main' | 'side' | 'daily',
    cefrLevel: string
  ): Promise<DropResult | null> {
    const rarity = this.rollRarity(questType)

    // Fetch random item of rolled rarity
    // ... DB query to select item

    // Check if player already has this item
    // ... duplicate check, convert to duplicate bonus

    return null // Placeholder
  }
}
```

**Step 2: Commit**

```bash
git add services/reward-service/
git commit -m "feat: add reward service with drop engine and rarity system"
```


---

## 阶段 7：CocosCreator 客户端（Week 4-9，与后端并行）

### Task 7.1: 项目初始化与网络层

**Files:**
- Create: `apps/game-client/settings/project.json`
- Create: `apps/game-client/assets/`
- Create: `apps/game-client/src/network/HttpClient.ts`
- Create: `apps/game-client/src/network/WebSocketClient.ts`
- Create: `apps/game-client/src/network/types.ts`

**Step 1: Create HTTP client wrapper**

```typescript
// apps/game-client/src/network/HttpClient.ts
const API_BASE = 'https://api.linguaquest.com/api/v1'

interface ApiResponse<T> {
  data?: T
  error?: { code: string; message: string }
}

export class HttpClient {
  private token: string | null = null

  setAuthToken(token: string) {
    this.token = token
  }

  async post<T>(path: string, body: any): Promise<ApiResponse<T>> {
    const response = await fetch(`${API_BASE}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {})
      },
      body: JSON.stringify(body)
    })

    const data = await response.json()

    if (!response.ok) {
      return { error: data.error || { code: 'UNKNOWN', message: 'Server error' } }
    }

    return { data }
  }

  async get<T>(path: string): Promise<ApiResponse<T>> {
    const response = await fetch(`${API_BASE}${path}`, {
      headers: {
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {})
      }
    })

    const data = await response.json()

    if (!response.ok) {
      return { error: data.error || { code: 'UNKNOWN', message: 'Server error' } }
    }

    return { data }
  }
}

export const http = new HttpClient()
```

**Step 2: Create WebSocket client for real-time coach hints**

```typescript
// apps/game-client/src/network/WebSocketClient.ts
export interface CoachHint {
  type: 'coach_hint'
  payload: {
    error: { type: string; correction: string; explanation: string }
    hint: string
  }
}

export class WebSocketClient {
  private ws: WebSocket | null = null
  private userId: string = ''
  private listeners: Map<string, Function[]> = new Map()

  connect(userId: string, token: string): void {
    this.userId = userId
    this.ws = new WebSocket(`wss://realtime.linguaquest.com/realtime/v1/websocket?apikey=${token}`)

    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data)
      if (data.event === 'coach_hint') {
        this.notify('coach_hint', data.payload)
      }
    }

    this.ws.onclose = () => {
      // Auto reconnect after 5s
      setTimeout(() => this.connect(this.userId, token), 5000)
    }
  }

  on(event: string, callback: Function): void {
    const list = this.listeners.get(event) || []
    list.push(callback)
    this.listeners.set(event, list)
  }

  private notify(event: string, payload: any): void {
    const callbacks = this.listeners.get(event) || []
    callbacks.forEach(cb => cb(payload))
  }

  disconnect(): void {
    this.ws?.close()
  }
}
```

**Step 3: Commit**

```bash
git add apps/game-client/src/network/
git commit -m "feat: add network layer with HTTP client and WebSocket for real-time coach hints"
```

---

### Task 7.2: 音频管理器与 VAD 检测器

**Files:**
- Create: `apps/game-client/src/audio/AudioManager.ts`
- Create: `apps/game-client/src/audio/VADDetector.ts`
- Create: `apps/game-client/src/audio/WakeWordDetector.ts`
- Create: `apps/game-client/src/audio/VoicePipeline.ts`
- Create: `apps/game-client/src/audio/types.ts`

**Step 1: Create audio manager**

```typescript
// apps/game-client/src/audio/AudioManager.ts
export class AudioManager {
  private audioContext: AudioContext | null = null
  private stream: MediaStream | null = null
  private source: MediaStreamAudioSourceNode | null = null

  async startCapture(sampleRate: number = 16000): Promise<MediaStream> {
    this.audioContext = new AudioContext({ sampleRate })
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
        sampleRate
      }
    })
    this.source = this.audioContext.createMediaStreamSource(this.stream)
    return this.stream
  }

  stopCapture(): void {
    this.stream?.getTracks().forEach(track => track.stop())
    this.audioContext?.close()
    this.stream = null
    this.source = null
  }

  async playAudio(url: string): Promise<void> {
    const audioBuffer = await this.loadAudio(url)
    if (!this.audioContext) return

    const source = this.audioContext.createBufferSource()
    source.buffer = audioBuffer
    source.connect(this.audioContext.destination)
    source.start()
  }

  private async loadAudio(url: string): Promise<AudioBuffer> {
    const response = await fetch(url)
    const arrayBuffer = await response.arrayBuffer()
    return this.audioContext!.decodeAudioData(arrayBuffer)
  }

  getAudioNode(): MediaStreamAudioSourceNode | null {
    return this.source
  }
}
```

**Step 2: Create VAD detector**

```typescript
// apps/game-client/src/audio/VADDetector.ts
export type VADState = 'silence' | 'speaking' | 'unknown'

export interface VADConfig {
  silenceThreshold: number  // Audio level threshold
  speechStartDelay: number  // ms to wait before declaring speaking
  speechEndDelay: number    // ms of silence before declaring end
}

export class VADDetector {
  private state: VADState = 'unknown'
  private config: VADConfig = {
    silenceThreshold: 0.01,
    speechStartDelay: 100,
    speechEndDelay: 1500  // 1.5s silence = end of turn
  }

  private analyser: AnalyserNode | null = null
  private rafId: number | null = null

  onSpeechStart: (() => void) | null = null
  onSpeechEnd: ((audioChunk: Float32Array) => void) | null = null
  onSilence: ((durationMs: number) => void) | null = null

  start(analyser: AnalyserNode): void {
    this.analyser = analyser
    this.detect()
  }

  stop(): void {
    if (this.rafId) {
      cancelAnimationFrame(this.rafId)
      this.rafId = null
    }
  }

  private detect(): void {
    if (!this.analyser) return

    const data = new Float32Array(this.analyser.fftSize)
    this.analyser.getFloatTimeDomainData(data)

    const rms = Math.sqrt(data.reduce((sum, val) => sum + val * val, 0) / data.length)

    if (rms > this.config.silenceThreshold && this.state !== 'speaking') {
      this.state = 'speaking'
      this.onSpeechStart?.()
    } else if (rms <= this.config.silenceThreshold && this.state === 'speaking') {
      // Silence detected, after delay declare speech end
      setTimeout(() => {
        if (this.state === 'speaking') {
          this.state = 'silence'
          this.onSpeechEnd?.(data)
        }
      }, this.config.speechEndDelay)
    }

    this.rafId = requestAnimationFrame(() => this.detect())
  }

  // For 5-second silence trigger (spirit coach hint)
  onSilenceDuration(durationMs: number): void {
    if (durationMs >= 5000) {
      this.onSilence?.(durationMs)
    }
  }
}
```

**Step 3: Create voice pipeline**

```typescript
// apps/game-client/src/audio/VoicePipeline.ts
import { AudioManager } from './AudioManager'
import { VADDetector } from './VADDetector'
import { http } from '../network/HttpClient'

export interface TurnResult {
  asr_text: string
  npc_text: string
  audio_url: string
  lxp_earned: number
}

export class VoicePipeline {
  private audioManager: AudioManager
  private vadDetector: VADDetector
  private audioChunks: Float32Array[] = []
  private onTurnComplete: ((result: TurnResult) => void) | null = null
  private onError: ((error: Error) => void) | null = null

  constructor() {
    this.audioManager = new AudioManager()
    this.vadDetector = new VADDetector()

    this.vadDetector.onSpeechStart = () => {
      this.audioChunks = []
    }

    this.vadDetector.onSpeechEnd = async (audioChunk) => {
      await this.processSpeech(audioChunk)
    }
  }

  async start(): Promise<void> {
    await this.audioManager.startCapture()
    const node = this.audioManager.getAudioNode()
    if (node) {
      this.vadDetector.start(node.context.createAnalyser())
    }
  }

  stop(): void {
    this.vadDetector.stop()
    this.audioManager.stopCapture()
  }

  private async processSpeech(audioChunk: Float32Array): Promise<void> {
    try {
      // Step 1: Encode to Opus/WAV and send to ASR
      const wavBlob = this.audioToWav(audioChunk)
      const formData = new FormData()
      formData.append('audio', wavBlob, 'speech.wav')
      formData.append('language', 'en')

      const { data: asrResult, error } = await http.post<{
        text: string;
        confidence: number;
        language: string
      }>('/voice/asr', formData)

      if (error || !asrResult) {
        this.onError?.(new Error(error?.message || 'ASR failed'))
        return
      }

      // Step 2: Send to dialogue service
      const { data: dialogueResult, error: dialogueError } = await http.post<any>('/dialogue', {
        npc_id: 'npc_merchant_01', // TODO: from current scene
        player_input: asrResult.text,
        session_id: 'current_session', // TODO: from session manager
        language: 'en'
      })

      if (dialogueError || !dialogueResult) {
        this.onError?.(new Error(dialogueError?.message || 'Dialogue failed'))
        return
      }

      // Step 3: Synthesize NPC response to speech
      const { data: ttsResult } = await http.post('/voice/tts', {
        text: dialogueResult.npc_text,
        voice_id: 'merchant'
      })

      // Step 4: Play audio
      if (ttsResult?.audio_url) {
        await this.audioManager.playAudio(ttsResult.audio_url)
      }

      this.onTurnComplete?.({
        asr_text: asrResult.text,
        npc_text: dialogueResult.npc_text,
        audio_url: ttsResult?.audio_url || '',
        lxp_earned: dialogueResult.lxp_earned || 0
      })
    } catch (err) {
      this.onError?.(err as Error)
    }
  }

  private audioToWav(samples: Float32Array): Blob {
    // WAV encoder implementation
    // ... convert Float32Array PCM samples to WAV blob
    const buffer = new ArrayBuffer(44 + samples.length * 2)
    const view = new DataView(buffer)
    // Write WAV header...
    // Write PCM data...
    return new Blob([buffer], { type: 'audio/wav' })
  }
}
```

**Step 4: Commit**

```bash
git add apps/game-client/src/audio/
git commit -m "feat: add audio pipeline with AudioManager, VAD, and VoicePipeline"
```


---

### Task 7.3: 游戏世界与场景管理

**Files:**
- Create: `apps/game-client/src/game/GameWorld.ts`
- Create: `apps/game-client/src/game/SceneManager.ts`
- Create: `apps/game-client/src/game/NPCManager.ts`
- Create: `apps/game-client/src/game/QuestOverlay.ts`

**Step 1: Create scene manager**

```typescript
// apps/game-client/src/game/SceneManager.ts
import { http } from '../network/HttpClient'

export interface SceneConfig {
  scene_id: string
  scene_name: string
  scene_type: string
  visual_assets_ref: string
  ambient_audio_ref: string
  npcs: Array<{ npc_id: string; position: { x: number; y: number } }>
  interactable_zones: Array<{
    zone_id: string
    trigger_type: 'proximity' | 'dialogue'
    action: string
  }>
}

export class SceneManager {
  private currentScene: SceneConfig | null = null
  private sceneAssets: Map<string, any> = new Map()

  async loadScene(sceneId: string): Promise<SceneConfig> {
    const { data, error } = await http.get<SceneConfig>(`/scenes/${sceneId}`)
    if (error || !data) throw new Error(`Failed to load scene: ${error?.message}`)

    this.currentScene = data
    await this.preloadAssets(data)
    return data
  }

  private async preloadAssets(scene: SceneConfig): Promise<void> {
    // Preload visual and audio assets
    // ... load textures, sprites, ambient audio
  }

  getAvailableNPCs(): Array<{ npc_id: string; position: { x: number; y: number } }> {
    return this.currentScene?.npcs || []
  }

  unlockNextScene(cefrLevel: string): string | null {
    // Check if user's CEFR level unlocks next scene
    // ... return next scene ID or null
    return null
  }
}
```

**Step 2: Commit**

```bash
git add apps/game-client/src/game/
git commit -m "feat: add game world management with scene loading and NPC positioning"
```

---

### Task 7.4: 精灵教练 UI 与奖励展示厅

**Files:**
- Create: `apps/game-client/src/ui/SpiritCoachUI.ts`
- Create: `apps/game-client/src/ui/RewardShowcaseUI.ts`
- Create: `apps/game-client/src/ui/QuestUI.ts`
- Create: `apps/game-client/src/ui/VocabularyBookUI.ts`

**Step 1: Create Spirit Coach UI**

```typescript
// apps/game-client/src/ui/SpiritCoachUI.ts
import { Node, Label, Sprite, tween, Vec3 } from 'cc'

export type CoachMood = 'correct' | 'suggestion' | 'needs_correction' | 'neutral'

export class SpiritCoachUI {
  private spriteNode: Node
  private hintLabel: Label
  private glowSprite: Sprite
  private isVisible: boolean = true

  constructor(rootNode: Node) {
    this.spriteNode = rootNode.getChildByName('SpiritSprite')!
    this.hintLabel = rootNode.getChildByName('HintLabel')!.getComponent(Label)!
    this.glowSprite = rootNode.getChildByName('Glow')!.getComponent(Sprite)!
  }

  showHint(text: string, mood: CoachMood): void {
    this.hintLabel.string = text
    this.setGlowColor(mood)
    this.animateHint()
  }

  private setGlowColor(mood: CoachMood): void {
    const colors: Record<CoachMood, [number, number, number]> = {
      correct: [0.2, 0.8, 0.2],      // Green
      suggestion: [1.0, 0.6, 0.2],    // Orange
      needs_correction: [1.0, 0.2, 0.2], // Red
      neutral: [1.0, 1.0, 0.8]        // Warm white
    }
    const [r, g, b] = colors[mood]
    this.glowSprite.color = new Color(r * 255, g * 255, b * 255, 200)
  }

  private animateHint(): void {
    this.spriteNode.setPosition(0, -50, 0)
    tween(this.spriteNode)
      .to(0.3, { position: new Vec3(0, 0, 0) })
      .start()
  }

  announceQuest(questTitle: string, questDescription: string): void {
    this.showHint(`New Quest: ${questTitle}\n${questDescription}`, 'neutral')
  }

  playCelebration(): void {
    // Special animation for quest completion / level up
  }
}
```

**Step 2: Commit**

```bash
git add apps/game-client/src/ui/
git commit -m "feat: add Spirit Coach UI with mood-based color feedback and reward showcase"
```

---

## 阶段 8：儿童模式与家长控制台（Week 9-10）

### Task 8.1: 儿童模式客户端守卫

**Files:**
- Create: `apps/game-client/src/security/ChildModeGuard.ts`
- Create: `apps/game-client/src/security/TimeManager.ts`

**Step 1: Create child mode guard**

```typescript
// apps/game-client/src/security/ChildModeGuard.ts
import { http } from '../network/HttpClient'
import { TimeManager } from './TimeManager'

export class ChildModeGuard {
  private isChildMode: boolean = false
  private timeManager: TimeManager
  private dailyLimitMinutes: number = 60

  async initialize(userId: string, accountType: string): Promise<void> {
    this.isChildMode = accountType === 'child'

    if (this.isChildMode) {
      // Fetch child account settings
      const { data: childAccount } = await http.get(`/child-accounts/${userId}`)
      if (childAccount) {
        this.dailyLimitMinutes = childAccount.daily_time_limit_minutes || 60
      }

      this.timeManager = new TimeManager(this.dailyLimitMinutes)
      this.timeManager.onTimeUp = () => this.handleTimeUp()

      // Block all social features
      this.blockSocialFeatures()
    }
  }

  private blockSocialFeatures(): void {
    // Disable: friend requests, public leaderboards, UGC, chat with other players
    // These are server-enforced, but client also hides UI
  }

  private handleTimeUp(): void {
    // Spirit coach voice: "Time to take a break! Your progress has been saved."
    // Auto-save and return to main menu
    http.post('/sessions/end', { reason: 'time_limit' })
  }

  async handleVoiceExit(): Promise<void> {
    if (this.isChildMode) {
      // Child said "我要休息" - emergency exit
      await http.post('/sessions/end', { reason: 'voice_exit' })
      // Navigate to main menu
    }
  }

  canAccessFeature(feature: string): boolean {
    if (!this.isChildMode) return true

    const blockedForChild = ['social', 'sharing', 'leaderboard_public', 'user_generated_content']
    return !blockedForChild.includes(feature)
  }
}
```

**Step 2: Create time manager**

```typescript
// apps/game-client/src/security/TimeManager.ts
export class TimeManager {
  private dailyLimitMinutes: number
  private usedToday: number = 0
  private sessionStart: number = 0
  private timerInterval: number | null = null

  onTimeUp: (() => void) | null = null
  onWarning: ((minutesLeft: number) => void) | null = null

  constructor(dailyLimitMinutes: number) {
    this.dailyLimitMinutes = dailyLimitMinutes
    this.startTimer()
  }

  private startTimer(): void {
    this.sessionStart = Date.now()

    this.timerInterval = window.setInterval(() => {
      const sessionMinutes = (Date.now() - this.sessionStart) / 60000
      const totalUsed = this.usedToday + sessionMinutes

      if (totalUsed >= this.dailyLimitMinutes) {
        this.onTimeUp?.()
        this.stopTimer()
      } else if (totalUsed >= this.dailyLimitMinutes - 5) {
        // 5 minute warning
        const minutesLeft = this.dailyLimitMinutes - totalUsed
        this.onWarning?.(Math.ceil(minutesLeft))
      }
    }, 30000) // Check every 30s
  }

  stopTimer(): void {
    if (this.timerInterval) {
      clearInterval(this.timerInterval)
      this.timerInterval = null
    }
    this.usedToday += (Date.now() - this.sessionStart) / 60000
  }

  getRemainingMinutes(): number {
    const sessionMinutes = (Date.now() - this.sessionStart) / 60000
    return Math.max(0, this.dailyLimitMinutes - this.usedToday - sessionMinutes)
  }
}
```

**Step 3: Commit**

```bash
git add apps/game-client/src/security/
git commit -m "feat: add child mode guard with time management and social feature blocking"
```

---

### Task 8.2: 家长控制台 Web 应用（Next.js）

**Files:**
- Create: `apps/parent-dashboard/package.json`
- Create: `apps/parent-dashboard/app/layout.tsx`
- Create: `apps/parent-dashboard/app/page.tsx`
- Create: `apps/parent-dashboard/app/dashboard/page.tsx`
- Create: `apps/parent-dashboard/app/settings/page.tsx`
- Create: `apps/parent-dashboard/lib/api.ts`
- Create: `apps/parent-dashboard/lib/auth.ts`

**Step 1: Create parent dashboard API client**

```typescript
// apps/parent-dashboard/lib/api.ts
const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'https://api.linguaquest.com/api/v1'

export async function getParentDashboard(token: string, parentId: string) {
  const res = await fetch(`${API_BASE}/parent/${parentId}/dashboard`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()
}

export async function getChildProgress(token: string, childId: string) {
  const res = await fetch(`${API_BASE}/parent/children/${childId}/progress`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()
}

export async function updateTimeLimit(token: string, childId: string, minutes: number) {
  const res = await fetch(`${API_BASE}/parent/children/${childId}/time-limit`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ daily_time_limit_minutes: minutes })
  })
  return res.json()
}

export async function deleteChildData(token: string, childId: string) {
  const res = await fetch(`${API_BASE}/parent/children/${childId}/data`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()
}
```

**Step 2: Create dashboard page**

```tsx
// apps/parent-dashboard/app/dashboard/page.tsx
'use client'

import { useState, useEffect } from 'react'
import { getParentDashboard, getChildProgress } from '../../lib/api'

export default function DashboardPage() {
  const [children, setChildren] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function loadDashboard() {
      const data = await getParentDashboard(getAuthToken(), getParentId())
      setChildren(data.children)
      setLoading(false)
    }
    loadDashboard()
  }, [])

  if (loading) return <div>Loading...</div>

  return (
    <main className="min-h-screen bg-gray-50 p-6">
      <h1 className="text-2xl font-bold mb-6">Parent Dashboard</h1>

      {children.map(child => (
        <ChildCard key={child.child_id} child={child} />
      ))}
    </main>
  )
}

function ChildCard({ child }: { child: any }) {
  return (
    <div className="bg-white rounded-lg shadow p-6 mb-4">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-semibold">{child.display_name}</h2>
        <span className="text-sm text-gray-500">
          Time today: {child.total_time_today}/{child.daily_time_limit_minutes} min
        </span>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <StatCard label="Vocabulary" value={child.vocabulary_count || 0} />
        <StatCard label="CEFR Level" value={child.cefr_level || 'A1'} />
        <StatCard label="Quests Done" value={child.quests_completed || 0} />
      </div>

      <div className="mt-4 flex gap-2">
        <a href={`/settings?child=${child.child_id}`} className="btn-secondary">
          Settings
        </a>
        <button className="btn-danger" onClick={() => handleDeleteData(child.child_id)}>
          Delete All Data
        </button>
      </div>
    </div>
  )
}

function StatCard({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="bg-gray-100 rounded p-3 text-center">
      <div className="text-2xl font-bold">{value}</div>
      <div className="text-sm text-gray-600">{label}</div>
    </div>
  )
}
```

**Step 3: Commit**

```bash
git add apps/parent-dashboard/
git commit -m "feat: add parent dashboard web app with Next.js"
```


---

## 阶段 9：集成测试与 MVP 发布准备（Week 11-12）

### Task 9.1: 端到端集成测试

**Files:**
- Create: `tests/e2e/voice-pipeline.test.ts`
- Create: `tests/e2e/quest-flow.test.ts`
- Create: `tests/e2e/child-mode.test.ts`
- Create: `tests/e2e/reward-drop.test.ts`
- Create: `tests/e2e/fixtures.ts`
- Create: `tests/e2e/README.md`

**Step 1: Create e2e test setup**

```typescript
// tests/e2e/fixtures.ts
import { test as base, expect } from '@playwright/test'

export const test = base.extend({
  context: async ({}, use) => {
    const context = await chromium.launchContext()
    await use(context)
    await context.close()
  }
})

export { expect }
```

**Step 2: Create voice pipeline e2e test**

```typescript
// tests/e2e/voice-pipeline.test.ts
import { test, expect } from './fixtures'

test.describe('Voice Pipeline E2E', () => {
  test('complete turn: player speaks → ASR → NPC responds → TTS plays', async ({ page }) => {
    // Navigate to game
    await page.goto('http://localhost:3000')

    // Mock microphone input (use synthetic audio)
    await page.evaluate(async () => {
      // Simulate VAD detecting speech
      window.__mockAudioInput__ = generateTestSpeech()
    })

    // Wait for NPC response
    await page.waitForSelector('[data-testid="npc-speech-bubble"]', { timeout: 5000 })

    const npcText = await page.getByTestId('npc-speech-bubble').textContent()
    expect(npcText).toBeTruthy()
    expect(npcText!.length).toBeGreaterThan(0)

    // Verify LXP was awarded
    const lxpDisplay = await page.getByTestId('lxp-earned')
    expect(lxpDisplay).toBeVisible()
  })

  test('wake word triggers spirit coach', async ({ page }) => {
    await page.goto('http://localhost:3000')

    // Simulate wake word
    await page.evaluate(() => window.__mockWakeWord__('小灵'))

    // Spirit coach should appear within 300ms
    const coachVisible = await page.waitForSelector('[data-testid="spirit-coach"]', { timeout: 500 })
    expect(coachVisible).toBeTruthy()
  })

  test('5 second silence triggers coach hint', async ({ page }) => {
    await page.goto('http://localhost:3000')

    // Start dialogue
    await page.getByTestId('start-dialogue').click()

    // Wait 5+ seconds without speaking
    await page.waitForTimeout(5500)

    // Coach hint should appear
    const hintVisible = await page.getByTestId('coach-hint')
    expect(hintVisible).toBeVisible()
  })
})
```

**Step 3: Create quest flow e2e test**

```typescript
// tests/e2e/quest-flow.test.ts
import { test, expect } from './fixtures'

test.describe('Quest Flow E2E', () => {
  test('accept and complete a main quest', async ({ page }) => {
    await page.goto('http://localhost:3000')

    // Enter marketplace scene
    await page.getByText('王都集市').click()

    // Accept quest from NPC
    await page.getByTestId('npc-merchant').click()
    await page.getByTestId('accept-quest').click()

    // Complete quest through dialogue
    await page.getByTestId('quest-objective').isVisible()

    // Simulate completing dialogue turns
    for (let i = 0; i < 3; i++) {
      await page.evaluate(() => window.__mockCompleteTurn__())
      await page.waitForTimeout(1000)
    }

    // Quest should be marked complete
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Radar chart should appear
    await expect(page.getByTestId('assessment-radar')).toBeVisible()
  })

  test('daily quests reset and appear', async ({ page }) => {
    await page.goto('http://localhost:3000')

    // Open quest panel
    await page.getByTestId('open-quests').click()

    // Should see 3 daily quests
    const dailyQuests = page.getByTestId('daily-quest-item')
    await expect(dailyQuests).toHaveCount(3)
  })
})
```

**Step 4: Run e2e tests**

Run: `npx playwright test tests/e2e/ --reporter=html`
Expected: All tests passing, HTML report generated

**Step 5: Commit**

```bash
git add tests/e2e/
git commit -m "test: add E2E integration tests for voice pipeline, quest flow, and child mode"
```

---

### Task 9.2: 性能测试与优化

**Files:**
- Create: `tests/performance/latency.test.ts`
- Create: `scripts/performance-report.ts`

**Step 1: Create latency test script**

```typescript
// tests/performance/latency.test.ts
import { describe, it, expect } from 'vitest'
import { performance } from 'perf_hooks'

describe('Performance Benchmarks', () => {
  it('voice pipeline P95 latency < 1.5s', async () => {
    const latencies: number[] = []

    for (let i = 0; i < 100; i++) {
      const start = performance.now()
      await simulateVoiceTurn()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    }

    latencies.sort((a, b) => a - b)
    const p95 = latencies[Math.floor(latencies.length * 0.95)]
    const p99 = latencies[Math.floor(latencies.length * 0.99)]
    const avg = latencies.reduce((a, b) => a + b, 0) / latencies.length

    console.log(`P95: ${p95.toFixed(0)}ms, P99: ${p99.toFixed(0)}ms, Avg: ${avg.toFixed(0)}ms`)

    expect(p95).toBeLessThan(1500)
    expect(p99).toBeLessThan(2500)
  })

  it('wake word detection < 300ms', async () => {
    const latencies: number[] = []

    for (let i = 0; i < 50; i++) {
      const start = performance.now()
      await simulateWakeWord()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    }

    const max = Math.max(...latencies)
    expect(max).toBeLessThan(300)
  })

  it('spirit coach analysis < 800ms P95', async () => {
    const latencies: number[] = []

    for (let i = 0; i < 50; i++) {
      const start = performance.now()
      await simulateCoachAnalysis()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    }

    latencies.sort((a, b) => a - b)
    const p95 = latencies[Math.floor(latencies.length * 0.95)]
    expect(p95).toBeLessThan(800)
  })
})

async function simulateVoiceTurn(): Promise<void> {
  // Simulate full pipeline call
  const response = await fetch('http://localhost:8002/api/v1/dialogue', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      npc_id: 'npc_merchant_01',
      player_input: 'How much does this apple cost?',
      session_id: 'test-session',
      language: 'en'
    })
  })
  return response.json()
}

async function simulateWakeWord(): Promise<void> {
  // Simulate wake word detection
  await fetch('http://localhost:8003/api/v1/coach/wake', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ user_id: 'test-user', language: 'zh' })
  })
}

async function simulateCoachAnalysis(): Promise<void> {
  await fetch('http://localhost:8003/api/v1/coach/analyze', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      turn_id: 'test-turn',
      asr_text: 'I goed to the store yesterday',
      user_id: 'test-user'
    })
  })
}
```

**Step 2: Commit**

```bash
git add tests/performance/ scripts/performance-report.ts
git commit -m "test: add performance benchmark tests for voice pipeline latency"
```

---

### Task 9.3: MVP 发布检查清单

**Step 1: 功能完整性检查**

- [ ] 语音交互管线端到端工作正常（P95 < 1.5s）
- [ ] 唤醒词检测（中/英）响应 < 300ms，误触发 < 1次/小时
- [ ] 精灵教练错误检测、任务播报、跟读练习正常工作
- [ ] 主线任务第1章完整可玩（至少5个任务）
- [ ] 支线任务至少3个可玩
- [ ] 日常任务每日重置3个
- [ ] 5种 NPC 各有独立语言风格和 TTS 音色
- [ ] 3个场景（集市/酒馆/公会）可正常切换
- [ ] 儿童账户创建流程完整（家长验证）
- [ ] 时间管理功能工作正常（到时自动退出）
- [ ] 家长仪表板可查看学习数据
- [ ] 内容安全过滤有效（红队测试通过）
- [ ] 3维雷达图正常显示
- [ ] 奖励掉落系统正常工作
- [ ] 奖励展示厅可查看和装备
- [ ] 免费/付费分层正确（前2章节免费体验）

**Step 2: 安全检查**

- [ ] 无硬编码密钥（使用环境变量/KMS）
- [ ] TLS 1.3 加密所有传输
- [ ] RLS 策略正确（家长只能访问自己的子账户）
- [ ] 儿童模式社交功能已屏蔽
- [ ] 内容安全过滤有效率 >= 99.9%
- [ ] JWT token 有效期 <= 24小时
- [ ] 数据库 PII 字段 AES-256 加密
- [ ] Snyk 扫描 0 Critical, 0 High

**Step 3: 性能检查**

- [ ] 语音管线 P95 < 1.5s
- [ ] 唤醒词响应 < 300ms
- [ ] 精灵教练分析 P95 < 800ms
- [ ] 客户端内存峰值 < 2GB（移动端）
- [ ] 崩溃率 < 0.5%
- [ ] 系统可用性 >= 99.5%

**Step 4: Commit final release**

```bash
git add -A
git commit -m "release: MVP v1.0.0 - LinguaQuest RPG Chapter 1 complete"
```

---

## 附录：快速参考

### 项目结构总览

```
linguaquest/
├── apps/
│   ├── game-client/              # CocosCreator 游戏客户端
│   │   ├── src/
│   │   │   ├── audio/           # 音频管线 (AudioManager, VAD, VoicePipeline)
│   │   │   ├── network/         # 网络层 (HTTP, WebSocket)
│   │   │   ├── game/            # 游戏逻辑 (Scene, NPC, Quest managers)
│   │   │   ├── ui/              # UI 组件 (SpiritCoach, RewardShowcase, QuestUI)
│   │   │   └── security/        # 安全 (ChildModeGuard, TimeManager)
│   │   └── assets/              # 游戏资源
│   └── parent-dashboard/         # Next.js 家长控制台
│       ├── app/
│       └── lib/
├── services/
│   ├── db/                       # 数据库迁移
│   │   └── migrations/          # 17 SQL 迁移文件
│   ├── auth-service/             # 认证服务 (Node.js/Fastify)
│   ├── dialogue-service/         # 对话服务 (Node.js/Fastify)
│   │   └── src/
│   │       ├── services/        # LLM Router, NPC Engine, Prompt Manager
│   │       └── routes/          # REST 端点
│   ├── voice-service/            # 语音服务 (Python/FastAPI)
│   │   └── src/
│   │       ├── services/        # Whisper, ElevenLabs
│   │       └── api/routes/      # ASR, TTS 端点
│   ├── spirit-coach-service/     # 精灵教练 (Node.js/Fastify)
│   │   └── src/
│   │       ├── services/        # Error Detector, Intervention Manager
│   │       └── workers/         # Redis 消息消费者
│   ├── quest-service/            # 任务服务 (Node.js/Fastify)
│   ├── assessment-service/       # 评估服务 (Python/FastAPI)
│   ├── reward-service/           # 奖励服务 (Node.js/Fastify)
│   └── content-filter-service/   # 内容安全 (Node.js/Fastify)
├── tests/
│   └── e2e/                     # Playwright 端到端测试
├── docker-compose.dev.yml        # 本地开发 Docker
└── .github/workflows/ci.yml      # CI/CD Pipeline
```

### 服务端口分配

| 服务 | 端口 | 语言 |
|------|------|------|
| Voice Service | 8001 | Python/FastAPI |
| Dialogue Service | 8002 | Node.js/Fastify |
| Spirit Coach Service | 8003 | Node.js/Fastify |
| Quest Service | 8004 | Node.js/Fastify |
| Assessment Service | 8005 | Python/FastAPI |
| Reward Service | 8006 | Node.js/Fastify |
| Content Filter | 8007 | Python/FastAPI |
| CMS (Strapi) | 8008 | Node.js |
| Parent Dashboard | 8009 | Next.js |
| Subscription | 8010 | Node.js/Fastify |

### 关键 API 端点

```
POST /api/v1/auth/register          # 用户注册
POST /api/v1/auth/login             # 用户登录
POST /api/v1/voice/asr              # 语音转文字
POST /api/v1/voice/tts              # 文字转语音
POST /api/v1/dialogue               # NPC 对话
POST /api/v1/coach/analyze           # 精灵教练分析
POST /api/v1/coach/wake             # 唤醒词触发
POST /api/v1/coach/hint             # 发送教练提示
GET  /api/v1/quests                  # 获取任务列表
POST /api/v1/quests/:id/complete    # 完成任务
GET  /api/v1/quests/daily           # 获取每日任务
POST /api/v1/assessment/micro       # 微评估计算
GET  /api/v1/rewards/showcase       # 获取奖励展示厅
POST /api/v1/rewards/equip          # 装备奖励物品
GET  /api/v1/parent/:id/dashboard   # 家长仪表板
PUT  /api/v1/parent/children/:id/time-limit  # 设置时间限制
```

