# 第一章魔法学院游戏世界与情节实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现第一章魔法学院冒险的完整游戏世界与情节内容，包括 3 个场景（精灵森林、咒语图书馆、彩虹花园）、5 个 NPC、故事线数据、徽章系统和教学内容配置，符合国内小学四年级英语教学大纲。

**Architecture:** 基于现有代码库架构（Fastify 微服务 + CocosCreator 客户端），新增场景数据配置、NPC 配置文件、教学内容数据库和徽章系统。

**Tech Stack:** Node.js/Fastify, Supabase PostgreSQL, TypeScript, JSON 配置文件

---

## 现状分析

已有基础代码：
- `services/`: 6 个微服务（auth, dialogue, content-filter, quest, reward, spirit-coach）
- `apps/game-client/`: CocosCreator 客户端骨架（SceneManager, NPCManager, QuestUI 等）
- `tests/`: E2E 和性能测试框架

---

## Task 1: 创建场景数据配置

**Files:**
- Create: `services/content-service/src/data/scenes.json`
- Modify: `services/content-service/src/routes/scenes.ts`

**场景数据结构（scenes.json）：**

```json
[
  {
    "scene_id": "spirit_forest",
    "scene_name": "精灵森林",
    "scene_name_en": "Spirit Forest",
    "order": 1,
    "description": "初识魔法，学习问候语、颜色和数字",
    "npcs": ["oakley"],
    "vocabulary_focus": ["greetings", "colors", "numbers"],
    "tasks": ["greet_oakley", "activate_flowers", "open_chest"],
    "badge_id": "forest_badge",
    "required_lxp": 30
  },
  {
    "scene_id": "spell_library",
    "scene_name": "咒语图书馆",
    "scene_name_en": "Spell Library",
    "order": 2,
    "description": "学习课堂用语和学习用品",
    "npcs": ["bookmark", "luna"],
    "vocabulary_focus": ["classroom_items", "commands", "actions"],
    "tasks": ["organize_books", "follow_commands", "practice_dialogue"],
    "badge_id": "library_badge",
    "required_lxp": 60
  },
  {
    "scene_id": "rainbow_garden",
    "scene_name": "彩虹花园",
    "scene_name_en": "Rainbow Garden",
    "order": 3,
    "description": "探索自然，学习天气、动物、方位",
    "npcs": ["petalia"],
    "vocabulary_focus": ["weather", "animals", "plants", "positions", "emotions"],
    "tasks": ["fix_weather_crystal", "find_lost_animals", "plant_flowers"],
    "badge_id": "garden_badge",
    "required_lxp": 90
  }
]
```

**Step 1: 创建 content-service 目录结构**

```bash
mkdir -p services/content-service/src/{data,routes,__tests__}
```

**Step 2: 创建 scenes.json**

```json
// services/content-service/src/data/scenes.json
[
  {
    "scene_id": "spirit_forest",
    "scene_name": "精灵森林",
    "scene_name_en": "Spirit Forest",
    "order": 1,
    "description": "初识魔法，学习问候语、颜色和数字",
    "npcs": ["oakley"],
    "vocabulary_focus": ["greetings", "colors", "numbers"],
    "tasks": ["greet_oakley", "activate_flowers", "open_chest"],
    "badge_id": "forest_badge",
    "required_lxp": 30
  },
  {
    "scene_id": "spell_library",
    "scene_name": "咒语图书馆",
    "scene_name_en": "Spell Library",
    "order": 2,
    "description": "学习课堂用语和学习用品",
    "npcs": ["bookmark", "luna"],
    "vocabulary_focus": ["classroom_items", "commands", "actions"],
    "tasks": ["organize_books", "follow_commands", "practice_dialogue"],
    "badge_id": "library_badge",
    "required_lxp": 60
  },
  {
    "scene_id": "rainbow_garden",
    "scene_name": "彩虹花园",
    "scene_name_en": "Rainbow Garden",
    "order": 3,
    "description": "探索自然，学习天气、动物、方位",
    "npcs": ["petalia"],
    "vocabulary_focus": ["weather", "animals", "plants", "positions", "emotions"],
    "tasks": ["fix_weather_crystal", "find_lost_animals", "plant_flowers"],
    "badge_id": "garden_badge",
    "required_lxp": 90
  }
]
```

**Step 3: 创建 scenes 路由**

```typescript
// services/content-service/src/routes/scenes.ts
import { FastifyInstance } from 'fastify'
import scenesData from '../data/scenes.json'

export async function registerSceneRoutes(server: FastifyInstance) {
  server.get('/scenes', async () => {
    return { success: true, data: scenesData }
  })

  server.get('/scenes/:sceneId', async (request, reply) => {
    const { sceneId } = request.params as { sceneId: string }
    const scene = scenesData.find(s => s.scene_id === sceneId)
    if (!scene) {
      return reply.code(404).send({ success: false, error: 'Scene not found' })
    }
    return { success: true, data: scene }
  })
}
```

**Step 4: Commit**

```bash
git add services/content-service/src/data/scenes.json services/content-service/src/routes/scenes.ts
git commit -m "feat: add scene data configuration for chapter 1"
```

---

## Task 2: 创建 NPC 配置文件

**Files:**
- Create: `services/content-service/src/data/npcs.json`
- Modify: `services/dialogue-service/src/services/npc-engine.ts`

**NPC 数据结构（npcs.json）：**

```json
[
  {
    "npc_id": "spark",
    "name": "Spark",
    "name_cn": "小灵",
    "role": "spirit_coach",
    "personality": "活泼热情，全程陪伴",
    "cefr_level": "A1",
    "voice_style": "cheerful_childlike",
    "greeting": "Hi! I'm Spark! Welcome to the Magic Academy!",
    "is_persistent": true
  },
  {
    "npc_id": "oakley",
    "name": "Oakley",
    "role": "forest_guardian",
    "personality": "智慧温和，语速较慢",
    "cefr_level": "A1",
    "voice_style": "wise_slow",
    "greeting": "Welcome, young student. I am Oakley, guardian of this forest.",
    "scene_id": "spirit_forest",
    "teaches": ["greetings", "colors", "numbers"]
  },
  {
    "npc_id": "bookmark",
    "name": "Bookmark",
    "role": "librarian",
    "personality": "博学稳重，慢慢来",
    "cefr_level": "A1",
    "voice_style": "calm_elderly",
    "greeting": "Welcome to the Spell Library. Take your time, young one.",
    "scene_id": "spell_library",
    "teaches": ["classroom_items", "commands"]
  },
  {
    "npc_id": "luna",
    "name": "Luna",
    "role": "apprentice",
    "personality": "活泼可爱，像好朋友",
    "cefr_level": "A1",
    "voice_style": "friendly_peer",
    "greeting": "Hey! I'm Luna! Let's practice magic spells together!",
    "scene_id": "spell_library",
    "teaches": ["actions", "dialogue_practice"]
  },
  {
    "npc_id": "petalia",
    "name": "Petalia",
    "role": "flower_fairy",
    "personality": "温柔耐心，充满母性关怀",
    "cefr_level": "A1",
    "voice_style": "gentle_warm",
    "greeting": "Hello dear! I'm Petalia. Can you help me with the garden?",
    "scene_id": "rainbow_garden",
    "teaches": ["weather", "animals", "positions", "emotions"]
  }
]
```

**Step 1: 创建 npcs.json**

**Step 2: 更新 NPCEngine 支持教学内容注入**

修改 `services/dialogue-service/src/services/npc-engine.ts`:
- 添加 `teaches` 字段到 NPCProfile
- 在教学模式中注入课程上下文到 system prompt
- 添加鼓励式反馈模板

**Step 3: Commit**

```bash
git add services/content-service/src/data/npcs.json
git commit -m "feat: add NPC configurations with teaching focus"
```

---

## Task 3: 创建教学内容数据库

**Files:**
- Create: `services/content-service/src/data/curriculum.json`

**对应四年级课标的教学分类：**

| 分类 | 场景 | 内容 |
|------|------|------|
| greetings | 精灵森林 | 问候与自我介绍 |
| colors | 精灵森林 | 颜色 |
| numbers | 精灵森林 | 数字 1-20 |
| classroom_items | 咒语图书馆 | 学习用品 |
| commands | 咒语图书馆 | 课堂指令 |
| actions | 咒语图书馆 | 动作动词 |
| weather | 彩虹花园 | 天气 |
| animals | 彩虹花园 | 动物 |
| plants | 彩虹花园 | 植物 |
| positions | 彩虹花园 | 方位 |
| emotions | 彩虹花园 | 情感 |

**Step 1: 创建 curriculum.json（包含所有教学项）**

**Step 2: Commit**

```bash
git add services/content-service/src/data/curriculum.json
git commit -m "feat: add curriculum data aligned with grade 4 English syllabus"
```

---

## Task 4: 创建内容服务（Content Service）

**Files:**
- Create: `services/content-service/package.json`
- Create: `services/content-service/tsconfig.json`
- Create: `services/content-service/src/index.ts`
- Create: `services/content-service/src/routes/scenes.ts`
- Create: `services/content-service/src/routes/npcs.ts`
- Create: `services/content-service/src/routes/curriculum.ts`

**服务端口**: 8308

**API 端点：**

```
GET /scenes                     - 获取所有场景
GET /scenes/:sceneId            - 获取场景详情
GET /scenes/:sceneId/npcs       - 获取场景 NPC
GET /npcs                       - 获取所有 NPC
GET /npcs/:npcId                - 获取 NPC 详情
GET /curriculum                 - 获取所有教学内容
GET /curriculum/:category       - 获取分类内容
GET /badges                     - 获取所有徽章
GET /story/chapter1             - 获取第一章故事线
```

**Step 1: 创建 package.json（参照其他服务格式）**

**Step 2: 创建 tsconfig.json**

**Step 3: 创建 index.ts 入口**

**Step 4: 创建所有路由文件**

**Step 5: 运行测试确保服务启动**

```bash
cd services/content-service && npm install && npm run build
```

**Step 6: Commit**

```bash
git add services/content-service/
git commit -m "feat: create content service for game world data"
```

---

## Task 5: 扩展徽章系统

**Files:**
- Create: `services/content-service/src/data/badges.json`
- Modify: `services/reward-service/src/routes/rewards.ts`

**徽章列表：**

| 徽章 | 解锁条件 | 奖励 |
|------|---------|------|
| Forest Badge | 完成精灵森林 | 颜色魔法特效 |
| Library Badge | 完成咒语图书馆 | 书本跟随宠物 |
| Garden Badge | 完成彩虹花园 | 彩虹背景 |
| Apprentice Title | 集齐 3 枚徽章 | 魔法学徒称号 |

**Step 1: 创建 badges.json**

**Step 2: 更新 reward-service 支持徽章解锁**

**Step 3: Commit**

---

## Task 6: 更新 NPC 引擎支持教学

**Files:**
- Modify: `services/dialogue-service/src/services/npc-engine.ts`
- Modify: `services/dialogue-service/src/services/prompt-manager.ts`

**改动：**
- 添加教学感知回复生成
- 场景上下文注入到 system prompt
- 鼓励式反馈模板（零负面反馈）
- 难度自适应（根据表现调整语言复杂度）

**Step 1: 编写测试用例**

```typescript
// services/dialogue-service/src/__tests__/npc-engine.test.ts
describe('Teaching-aware NPC responses', () => {
  it('should inject curriculum context into responses', async () => { ... })
  it('should use encouraging feedback on wrong answers', async () => { ... })
  it('should adapt difficulty based on performance', async () => { ... })
})
```

**Step 2: 实现功能**

**Step 3: 测试通过**

**Step 4: Commit**

---

## Task 7: 更新任务引擎支持故事线

**Files:**
- Modify: `services/quest-service/src/services/quest-engine.ts`

**改动：**
- 替换现有的 placeholder quest 为第一章故事线任务
- 添加 3 个场景的主线任务
- 添加每个场景的子任务
- 添加星星计数和徽章解锁逻辑

**Step 1: 编写测试**

**Step 2: 实现 quest engine**

**Step 3: Commit**

---

## Task 8: 更新精灵教练服务

**Files:**
- Modify: `services/spirit-coach-service/src/services/error-detector.ts`

**改动：**
- 添加教学内容匹配（检测是否使用了课标词汇）
- 添加沉默超时引导（10s 无响应）
- 添加连错降级逻辑（连续 3 次错误自动降低难度）
- 添加中文辅助模式
- 添加连击奖励检测

**Step 1: 编写测试**

**Step 2: 实现**

**Step 3: Commit**

---

## Task 9: 更新客户端数据层

**Files:**
- Modify: `apps/game-client/src/game/SceneManager.ts`
- Modify: `apps/game-client/src/game/NPCManager.ts`
- Modify: `apps/game-client/src/game/GameWorld.ts`
- Modify: `apps/game-client/src/ui/QuestUI.ts`
- Modify: `apps/game-client/src/ui/RewardShowcaseUI.ts`

**改动：**
- 更新场景数据接口
- 添加 NPC 教学属性
- 添加徽章展示 UI
- 添加故事线进度管理

**Step 1: 编写测试**

**Step 2: 实现**

**Step 3: Commit**

---

## Task 10: 创建数据库迁移

**Files:**
- Create: `migrations/005_scenes.sql`
- Create: `migrations/006_npcs.sql`
- Create: `migrations/007_curriculum.sql`
- Create: `migrations/008_badges.sql`

**表结构：**

```sql
-- 005_scenes.sql
CREATE TABLE scenes (
  scene_id VARCHAR(50) PRIMARY KEY,
  scene_name VARCHAR(100) NOT NULL,
  scene_name_en VARCHAR(100) NOT NULL,
  scene_order INTEGER NOT NULL,
  description TEXT,
  npcs JSONB,
  vocabulary_focus JSONB,
  tasks JSONB,
  badge_id VARCHAR(50),
  required_lxp INTEGER DEFAULT 0
);

-- 006_npcs.sql
CREATE TABLE npcs (
  npc_id VARCHAR(50) PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  name_cn VARCHAR(100),
  role VARCHAR(50),
  personality TEXT,
  cefr_level VARCHAR(10) DEFAULT 'A1',
  voice_style VARCHAR(50),
  greeting TEXT,
  scene_id VARCHAR(50) REFERENCES scenes(scene_id),
  teaches JSONB,
  is_persistent BOOLEAN DEFAULT false
);

-- 007_curriculum.sql
CREATE TABLE curriculum_items (
  id SERIAL PRIMARY KEY,
  category VARCHAR(50) NOT NULL,
  category_cn VARCHAR(50) NOT NULL,
  text_en TEXT NOT NULL,
  text_cn TEXT,
  audio_ref VARCHAR(100),
  metadata JSONB
);

-- 008_badges.sql
CREATE TABLE user_badges (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  badge_id VARCHAR(50) NOT NULL,
  earned_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, badge_id)
);
```

**Step 1: 创建迁移文件**

**Step 2: 运行迁移**

**Step 3: Commit**

---

## Task 11: 编写集成测试

**Files:**
- Create: `tests/e2e/chapter1-flow.test.ts`

**测试场景：**
1. 完整第一章流程（开场 → 森林 → 图书馆 → 花园）
2. 徽章收集流程
3. 教学内容互动
4. 精灵教练介入时机
5. 降级与重试逻辑

**Step 1: 编写测试**

**Step 2: 运行测试**

**Step 3: Commit**

---

## Task 12: 清理与最终提交

**Steps:**
1. 运行所有测试确保通过
2. 运行 lint 检查
3. 删除临时文件（test-write.md 等）
4. 最终 commit

```bash
npm run test && npm run lint
git add .
git commit -m "feat: complete chapter 1 game world and plot implementation"
```

---

## 执行顺序总结

```
Task 1: 场景数据 (scenes.json + routes)
  ↓
Task 2: NPC 配置 (npcs.json + NPC engine)
  ↓
Task 3: 教学内容 (curriculum.json)
  ↓
Task 4: Content Service (完整服务)
  ↓
Task 5: 徽章系统 (badges.json + rewards)
  ↓
Task 6: NPC 引擎教学增强
  ↓
Task 7: 任务引擎故事线
  ↓
Task 8: 精灵教练教学引导
  ↓
Task 9: 客户端数据层
  ↓
Task 10: 数据库迁移
  ↓
Task 11: 集成测试
  ↓
Task 12: 清理与最终提交
```
