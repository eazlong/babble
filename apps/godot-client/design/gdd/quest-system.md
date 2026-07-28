# Quest System GDD

**系统名称**: Quest System (任务系统)
**版本**: 1.0
**日期**: 2026-06-24
**所属游戏**: LinguaQuest RPG (babble)
**负责服务**: quest-service
**依赖系统**: content-service, dialogue-service, assessment-service, reward-service, spirit-coach-service, voice-service（上游 ASR）, star-economy（下游星辉映射）, lxp-system（下游 LXP 累积）, parent-dashboard（下游进度报告）, Godot 客户端（下游 UI）

---

## 1. 概述

任务系统是 LinguaQuest RPG 的核心内容驱动系统，负责生成、分发、追踪和完成所有玩家可执行的任务。系统分为**主线任务**（场景进度驱动）和**日常任务**（习惯养成驱动）两大类型，与 LXP 评估、星级经济、奖励系统深度集成。

任务系统的设计目标：
- **学习路径清晰**: 主线任务按 CEFR A1 课标词汇顺序编排
- **习惯养成**: 日常任务每日刷新，培养持续学习习惯
- **无挫败感**: 任务失败不惩罚，飞飞 介入引导完成
- **动态难度**: 根据玩家表现自动调节任务难度

---

## 2. 玩家幻想

**玩家应该感觉**: "每天都有新挑战，完成任务就能获得星辉和奖励"

**情感设计**：

| 情感目标 | 设计实现 | 具体表现 |
|---------|---------|---------|
| **目标感** | 清晰的任务列表和目标 | 屏幕侧边显示当前任务，飞飞 提示"下一个任务：和 TreeSpirit 打招呼" |
| **成就感** | 任务完成的仪式反馈 | 任务完成时播放音效+粒子特效，显示"Task Completed!" |
| **期待感** | 日常任务的每日刷新 | 每日首次进入游戏时 飞飞 展示"今日任务"，带神秘感 |
| **安全感** | 任务失败不惩罚 | 任务可无限重试，飞飞 在困难时提供选项提示 |
| **成长感** | 任务难度渐进提升 | 从口语重复到自由对话的清晰难度曲线 |

**任务类型视觉映射**：
- **口语重复 (Repeat)**: 任务图标显示"语音波形"，提示"跟我读"
- **听力理解 (Listen)**: 任务图标显示"耳朵"，提示"听一听"
- **图片描述 (Describe)**: 任务图标显示"画笔"，提示"说一说"
- **自由对话 (Converse)**: 任务图标显示"对话气泡"，提示"聊一聊"

---

## 3. 详细规则

### 3.1 任务类型分类

#### 3.1.1 主线任务 (Main Quests)

**定义**: 推动场景剧情进度的任务，每个场景包含 3-4 个主线任务，必须按顺序完成。

**任务配置表**：

| 场景 | 主线任务数 | 任务序列 | 对应课标词汇 |
|------|-----------|----------|-------------|
| MistyBay | 3 | Greeting → Color → Nature | Hello, Hi, Red, Blue, Tree, Flower |
| WordSpiritLibrary | 4 | Classroom → Spell → Request → Magic | Stand up, Sit down, Please, Can I... |
| LanternCourtyard | 4 | Number → Count → Describe → Create | One to Twenty, How many..., Big/Small |

**主线任务状态机**：
```
[LOCKED] → [AVAILABLE] → [IN_PROGRESS] → [COMPLETED]
              ↑               ↓
           [FAILED] → [RETRY] → [IN_PROGRESS]
```

**状态转换规则**：
| 转换 | 触发条件 | 飞飞 行为 |
|------|---------|-----------|
| LOCKED → AVAILABLE | 前置任务完成 | 飞飞 飞出提示"新任务解锁！" |
| AVAILABLE → IN_PROGRESS | 玩家接近任务 NPC | NPC 主动对话，任务开始 |
| IN_PROGRESS → COMPLETED | 评估达到 3 星 | 播放完成动画，发放星辉 |
| IN_PROGRESS → FAILED | 连续 3 次 1-2 星 | 飞飞 介入，提供选项辅助 |
| FAILED → RETRY | 玩家选择重试 | 任务难度降低一级 |

#### 3.1.2 日常任务 (Daily Quests)

**定义**: 每日刷新的补充任务，用于培养学习习惯和获得额外奖励。

**生成规则**：
- **每日数量**: 3 个日常任务
- **刷新时间**: 每日 UTC+8 00:00
- **任务池**: 8 个预定义任务循环
- **难度调节**: 基于玩家近期平均 LXP 动态调整

**日常任务池 (8 个)**：

| ID | 任务名称 | 类型 | 描述 | 预期星辉 |
|----|---------|------|------|---------|
| DQ01 | 晨间问候 | 口语重复 | 向 飞飞 说早安问候语 | 1 |
| DQ02 | 听音辨词 | 听力理解 | 听 NPC 发音，选择正确图片 | 1 |
| DQ03 | 描述花园 | 图片描述 | 描述 LanternCourtyard 中的植物颜色 | 2 |
| DQ04 | 自由聊天 | 自由对话 | 和 飞飞 自由对话 3 轮 | 2-3 |
| DQ05 | 词汇复习 | 口语重复 | 复习昨日学过的 3 个词汇 | 1 |
| DQ06 | 听力挑战 | 听力理解 | 听一段对话并回答问题 | 1 |
| DQ07 | 创意描述 | 图片描述 | 用形容词描述指定物品 | 2 |
| DQ08 | 角色扮演 | 自由对话 | 扮演学生向老师提问 | 2-3 |

**每日任务选择算法**：
```typescript
function selectDailyQuests(completedQuests: string[], playerAvgLXP: number): string[] {
    // 1. 过滤已完成和近期做过的任务
    const availablePool = DAILY_QUEST_POOL.filter(q =>
        !completedQuests.includes(q.id) &&
        !q.lastCompletedWithin(3_days)
    );

    // 2. 基于 LXP 调整难度分布（修复逻辑错误）
    let difficultyDistribution: number[];
    if (playerAvgLXP >= 80) {
        difficultyDistribution = [1, 2, 2]; // 1个简单，2个中等
    } else if (playerAvgLXP >= 60) {
        difficultyDistribution = [2, 1, 2]; // 平衡分布
    } else {
        difficultyDistribution = [3, 0, 0]; // 3个简单（而非[3,1,1]）
    }

    // 3. 随机选择并排序
    const selected = weightedRandomSelect(availablePool, difficultyDistribution, 3);
    return shuffle(selected); // 随机顺序呈现
}
```

**修复说明**：
- 原算法：LXP < 60 时 difficultyDistribution = [3, 1, 1]，但只有 3 个任务槽位，导致逻辑错误
- 修复后：LXP < 60 时改为 [3, 0, 0]，全部选择简单任务
- 确保分布数组总和始终等于任务槽位数（3）

#### 3.1.3 主线任务重玩机制

**已完成的场景可以重复进入刷星**（与 star-economy.md §3.3 每日重置对齐）：

| 规则 | 说明 |
|------|------|
| 已完成主线任务可重玩 | 玩家可重复进入已完成的场景，重新执行任务获取星辉和 LXP |
| 剧情推进不重复 | 仅首次完成推进场景剧情和解锁下一场景 |
| 场景 神器徽记 不重复解锁 | 每个场景 神器徽记 仅解锁一次 |
| 每日重置 | 每日首次进入场景时，场景星辉计数器清零（与 star-economy §3.3 对齐） |
| 日常任务独立 | 日常任务不受主线重玩影响，按每日刷新规则独立运行 |

**设计意图**：允许高水平玩家通过重玩提升表现、积攒星辉用于商店消费，与 star-economy 的"场景可重复刷星"机制一致。

### 3.2 动态难度调整（DDR）

系统分两层 DDR，触发阈值和响应强度不同：

**基本 DDR**（每任务后检查，仅调整 quest 难度等级）：

```
基于最近 3 次任务的 avgLXP:
IF avgLXP < 40:
    - 下任务难度降一级（最低 Level 1）
    - 飞飞 提示"让我帮你一起完成这个简单的任务"
IF 当前场景连续 3 次任务评估 avgLXP >= 80:
    - 下任务难度升一级（最高 Level 4）
    - 飞飞 提示"你做得真棒！试试更难的任务吧"
```

完整公式见 §4.4 `shouldTriggerBasicDDR` / `calculateDDRAdjustment`。

**干预级 DDR**（跨系统安全网，触发 飞飞 介入 + 保底机制）：

建立跨系统共享的 `player_struggle_score`（与 spirit-coach.md §3.5、star-economy.md §5.2 对齐），确保 飞飞 介入和任务降级同步触发：

```typescript
struggle_score = (
  (consecutive_low_lxp >= 3 ? 1 : 0) +  // LXP < 40（来自 assessment）
  (consecutive_errors >= 3 ? 1 : 0) +    // grammar/pronunciation 错误
  (asr_failure_rate > 0.5 ? 1 : 0)       // ASR 置信度 < 0.3 的比例
) / 3

if struggle_score >= 0.67:
  trigger_spark_intervention()           // 飞飞 介入
  activate_quest_ddr()                   // Quest 系统降级
  // Star Economy 启动保底机制（最低 2 星）— 由 star-economy 响应
```

**两层关系**：基本 DDR 是常规调节（每任务后），干预级 DDR 是安全网（多维信号同时恶化时触发）。两者可同时生效：基本 DDR 降级难度，干预级 DDR 同时触发 飞飞 辅助和保底。

**难度等级定义**：

| 等级 | LXP 范围 | 任务类型分布 | 描述 |
|------|---------|-------------|------|
| Level 1 | 0-50 | 口语重复 60%, 听力理解 40% | 基础输入，鼓励开口 |
| Level 2 | 51-70 | 口语重复 30%, 听力理解 40%, 图片描述 30% | 逐步过渡 |
| Level 3 | 71-85 | 听力理解 30%, 图片描述 50%, 自由对话 20% | 输出为主 |
| Level 4 | 86-100 | 图片描述 40%, 自由对话 60% | 高阶表达 |

### 3.3 任务进度追踪

**进度数据结构**：

```typescript
interface QuestProgress {
    questId: string;
    playerId: string;
    status: 'locked' | 'available' | 'in_progress' | 'completed' | 'failed';
    currentAttempt: number;          // 当前尝试次数
    maxAttempts: number;            // 最大尝试次数（-1 表示无限）
    starsEarned: number;            // 已获得星辉
    targetStars: number;            // 目标星辉数（来自 star-economy 动态阈值 calculate_artifact_mark_threshold）
    startTime: string;              // ISO 8601
    lastUpdateTime: string;
    lxpHistory: number[];             // 每次尝试的 LXP
    bestLXP: number;                 // 历史最高 LXP
    difficultyLevel: number;          // 当前难度等级 1-4
    ddrActive: boolean;             // 动态难度调整是否激活
}

interface DailyQuestState {
    date: string;                    // YYYY-MM-DD
    quests: DailyQuestEntry[];
    completedCount: number;         // 今日已完成数
    totalCount: number;              // 总是 3
    lastResetTime: string;
}

interface DailyQuestEntry {
    questId: string;
    status: 'available' | 'completed' | 'expired';
    completedAt?: string;
    starsEarned: number;
}
```

**进度保存策略**：
- **自动保存**: 每次任务状态变更时自动保存到 Supabase
- **本地缓存**: Godot 客户端本地缓存，网络恢复后同步
- **会话级恢复**: 异常退出后，下次启动恢复任务进度

### 3.4 任务奖励（与 Star Economy 对齐）

**任务类型与典型星辉范围**（基于 star-economy.md §4.1 LXP→星辉映射，按任务复杂度估算典型区间）：

| 任务类型 | 典型星辉范围 | 任务数量/场景 | 说明 |
|---------|-------------|--------------|------|
| 口语重复 | 1-2 星 | 1 | 跟读 1-3 词，典型 LXP 40-65 |
| 听力理解 | 1-3 星 | 1-2 | 选择正确答案，典型 LXP 40-75 |
| 图片描述 | 2-4 星 | 1 | 组织 3-5 词描述，典型 LXP 60-85 |
| 自由对话 | 2-4 星 | 0-1 | 多轮自由表达，典型 LXP 55-85 |

> **注意**：实际星辉数由 assessment-service 按 LXP 公式计算后经 star-economy 映射得到，上表仅为场景平衡设计参考。

**任务完成奖励**：

```
主线任务完成:
    - 星辉: 按 LXP 映射 1-5 星
    - LXP: 按 LXP 系统公式计算
    - 金币: 基础 10 金币 × 星辉数
    - 进度: 累计到场景星级总数
    
日常任务完成:
    - 星辉: 按 LXP 映射 1-5 星（与主线任务相同）
    - LXP: 按 §4.2 `calculateDailyQuestLXP` 公式计算（含连续完成加成，第3个全完成最高 1.4x）
    - 金币: 基础 15 金币 × 星辉数
    - 额外: 3个日常任务全部完成 → 额外 50 金币 + "每日之星" 徽章
```

**每日完成全奖励**：

```
IF 今日 3 个日常任务全部完成:
    - 额外金币: 50
    - 额外 LXP: 50
    - 特殊奖励: "Daily Star" 徽章（仅当日有效）
    - 飞飞 祝贺动画: "太棒了！你完成了今天的所有任务！"
```

### 3.5 任务失败处理（飞飞 介入、保底机制）

**无失败惩罚原则**：
- 任务永远不会"失败"导致进度丢失
- 低表现触发 飞飞 介入辅助，而非惩罚

**飞飞 介入矩阵**：

| 场景 | 检测条件 | 飞飞 行为 | 保底效果 |
|------|---------|-----------|---------|
| 连续低星 | 当前任务 3 次尝试 < 40 LXP | 飞飞 提供选项提示（A/B/C 选择） | 下次最低获得 2 星 |
| 长期停滞 | 单任务时长 > 5 分钟 | 飞飞 建议"休息一会儿再继续" | 自动保存进度 |
| ASR 困难 | 连续 3 次 ASR 置信度 < 0.3 | 飞飞 降低任务难度，改为单词级 | 显示单词卡片辅助 |
| 完全卡住 | 玩家说"我不会"或静默 > 15s | 飞飞 播放示范音频，允许跟读 | 跟读即算 2 星完成 |

**三层保底体系**（与 star-economy.md、lxp-system.md 分层协作）：

| 层级 | 触发条件 | 效果 | 来源 |
|------|---------|------|------|
| **第一层：单回复保底** | 同一任务第 3 次尝试，raw_lxp < 40 | 该回复保底 40 分（2 星） | lxp-system.md `MIN_SCORE_RETRY_3` |
| **第二层：基本 DDR 降级** | 最近 3 次任务 avgLXP < 40 | 下任务难度降一级 | 本 GDD §3.2 / §4.4 `shouldTriggerBasicDDR` |
| **第三层：场景级保底解锁（安全网）** | 场景内总回复数 > 25 次 AND 当前场景星辉 < threshold | 后续所有回复最低 2 星，飞飞 提示"你已经很努力啦，让我帮你一起完成！" | 本段下方 |

**场景级保底解锁详细规则**：

```
IF 场景内总回复数 > 25 次 AND 当前星辉 < threshold:
    - 触发"保底解锁"模式
    - 剩余所需星辉自动按 2 星/回复计算
    - 飞飞 提示"你已经很努力啦，让我帮你一起完成！"
    - 所有后续回复最低获得 2 星
```

**对应调节旋钮**：`FLOOR_ATTEMPTS_TRIGGER = 25`（场景级），`FLOOR_STARS_MIN = 2`（每层保底最低星数）。

### 3.6 与 quest-service 的技术接口

**HTTP API 接口**：

```typescript
// GET /api/quests/main/:playerId/:sceneId
// 获取玩家在某场景的主线任务列表
interface GetMainQuestsResponse {
    sceneId: string;
    quests: MainQuest[];
    currentQuestId: string | null;  // 当前进行中任务
    sceneStars: number;             // 场景当前星辉总数
    artifact_markUnlocked: boolean;
}

// GET /api/quests/daily/:playerId
// 获取玩家今日日常任务
interface GetDailyQuestsResponse {
    date: string;
    quests: DailyQuest[];
    completedCount: number;
    allCompleted: boolean;
    bonusClaimed: boolean;
}

// POST /api/quests/progress/:questId
// 更新任务进度
interface UpdateQuestProgressRequest {
    playerId: string;
    questId: string;
    status: 'in_progress' | 'completed';
    starsEarned: number;
    lxpScore: number;
    attemptCount: number;
}

// POST /api/quests/complete/:questId
// 完成任务
interface CompleteQuestRequest {
    playerId: string;
    questId: string;
    finalLXP: number;
    totalStars: number;
    attempts: number;
}

interface CompleteQuestResponse {
    success: boolean;
    rewards: {
        stars: number;
        lxp: number;
        coins: number;
        items?: string[];
    };
    nextQuestId?: string;  // 解锁的下一个任务
}
```

**WebSocket 实时事件**：

```typescript
// 任务状态变更事件
interface QuestStatusEvent {
    event_type: 'quest_status_changed';
    player_id: string;
    quest_id: string;
    old_status: string;
    new_status: string;
    timestamp: string;
    session_id: string;
}

// 日常任务刷新事件
interface DailyQuestRefreshEvent {
    event_type: 'daily_quests_refreshed';
    player_id: string;
    date: string;
    new_quests: string[];
    timestamp: string;
}

// 飞飞 介入事件（发送到 spirit-coach-service）
interface 飞飞InterventionEvent {
    event_type: 'spark_intervention_needed';
    player_id: string;
    quest_id: string;
    reason: 'low_performance' | 'stuck' | 'asr_difficulty';
    current_attempt: number;
    avg_lxp: number;
    timestamp: string;
}
```

---

## 4. 公式

### 4.1 任务难度评分计算

```typescript
function calculateQuestDifficulty(
    taskType: TaskType,
    vocabularyCount: number,
    requiredResponseLength: number
): number {
    // 基础难度分 (1-10)
    const typeDifficulty: Record<TaskType, number> = {
        'repeat': 2,
        'listen': 3,
        'describe': 5,
        'converse': 7
    };
    
    const baseDifficulty = typeDifficulty[taskType];
    
    // 词汇复杂度加成
    const vocabBonus = Math.min(vocabularyCount * 0.5, 3);
    
    // 长度复杂度加成
    const lengthBonus = Math.min(requiredResponseLength * 0.1, 2);
    
    // 最终难度 (1-10)
    const finalDifficulty = Math.min(10, baseDifficulty + vocabBonus + lengthBonus);
    
    return Math.round(finalDifficulty);
}
```

**变量表**：
| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `taskType` | enum | repeat/listen/describe/converse | 任务类型 |
| `vocabularyCount` | int | 1-20 | 任务涉及的新词汇数量 |
| `requiredResponseLength` | int | 1-50 | 期望回答的单词数 |
| `baseDifficulty` | int | 2-7 | 类型基础难度 |
| `finalDifficulty` | int | 1-10 | 最终难度评分 |

### 4.2 日常任务 LXP 加成计算

```typescript
function calculateDailyQuestLXP(
    baseLXP: number,
    questIndex: number,      // 0-2，第几个日常任务
    allCompleted: boolean    // 是否全部完成
): number {
    // 基础加成
    let bonus = 1.0;
    
    // 连续完成加成 (第1个 1.0x, 第2个 1.1x, 第3个 1.2x)
    bonus += questIndex * 0.1;
    
    // 全部完成额外加成
    if (allCompleted && questIndex === 2) {
        bonus += 0.2;
    }
    
    return Math.round(baseLXP * bonus);
}
```

**计算示例**：
- 第1个日常任务，基础 LXP 60：60 × 1.0 = **60 LXP**
- 第2个日常任务，基础 LXP 60：60 × 1.1 = **66 LXP**
- 第3个日常任务，基础 LXP 60（全部完成）：60 × 1.4 = **84 LXP**

### 4.3 任务进度百分比

```typescript
function calculateQuestProgress(
    currentStars: number,
    targetStars: number    // 来自 star-economy 动态阈值 calculate_artifact_mark_threshold(scene_id, player_avg_stars)
): number {
    return Math.min(100, Math.round((currentStars / targetStars) * 100));
}
```

**进度映射**（以 MistyBay 中等玩家 threshold=15 为例）：
| 星辉占比 | 进度百分比 | 飞飞 提示语 |
|--------|-----------|-------------|
| 0-25% | 0-25% | "刚开始，加油！" |
| 25-50% | 25-50% | "已经四分之一啦！" |
| 50-75% | 50-75% | "过半啦，继续！" |
| 75-100% | 75-100% | "就差一点点，冲刺！" |
| >= 100% | 100% | "徽章解锁！太棒了！" |

### 4.4 基本 DDR 公式（§3.2 第一层）

```typescript
function shouldTriggerBasicDDR(
    recentLXPs: number[],      // 最近 N 次任务的 LXP
    threshold: number = 40
): boolean {
    if (recentLXPs.length < 3) return false;
    
    // 取最近 3 次
    const lastThree = recentLXPs.slice(-3);
    const avgLXP = lastThree.reduce((a, b) => a + b, 0) / 3;
    
    return avgLXP < threshold;
}

function calculateBasicDDRAdjustment(
    currentLevel: number,
    avgLXP: number
): number {
    // LXP < 40: 降级
    if (avgLXP < 40) return Math.max(1, currentLevel - 1);
    
    // LXP > 80: 升级
    if (avgLXP > 80) return Math.min(4, currentLevel + 1);
    
    // 其他情况保持
    return currentLevel;
}
```

### 4.5 任务预期时间估算

```typescript
function estimateQuestTime(
    taskType: TaskType,
    estimatedAttempts: number = 2
): number {
    // 基础时间（秒）
    const baseTimes: Record<TaskType, number> = {
        'repeat': 30,      // 听提示 + 跟读
        'listen': 45,      // 听音频 + 选择 + 确认
        'describe': 90,    // 观察 + 组织语言 + 描述
        'converse': 120    // 多轮对话
    };
    
    // 考虑重试时间（每次重试增加 70%）
    let totalTime = 0;
    for (let i = 0; i < estimatedAttempts; i++) {
        totalTime += baseTimes[taskType] * Math.pow(0.7, i);
    }
    
    return Math.round(totalTime);
}
```

**场景预期时间计算**：
```typescript
// MistyBay 场景（3 个任务：口语重复 + 听力理解 + 图片描述）
estimatedSceneTime = estimateQuestTime('repeat', 2) + 
                     estimateQuestTime('listen', 2) + 
                     estimateQuestTime('describe', 2);
// = 30×1.7 + 45×1.7 + 90×1.7 ≈ 282s ≈ 4.7 分钟（基础）
// + NPC 对话和动画时间 ≈ 10-15 分钟（总场景时长）
```

---

## 5. 边缘情况

### 5.1 网络中断场景

| 场景 | 检测条件 | 处理策略 | 数据恢复 |
|------|---------|---------|---------|
| 任务进行中断网 | WebSocket 断开 > 5s | 提示"网络开小差了"，暂停任务计时 | 网络恢复后自动同步进度 |
| 任务完成时断网 | POST 请求失败 | 本地缓存完成状态，显示"稍后同步" | 网络恢复后自动重试提交 |
| 日常任务刷新时断网 | GET /daily 失败 | 使用本地缓存的昨日任务（标记为过期） | 恢复后刷新并补偿 |

**离线模式支持**：
```
IF 网络断开:
    - 切换到离线评估模式（简化版 LXP 计算）
    - 任务进度本地存储 (SQLite)
    - 限制：只能进行主线任务，日常任务需联网
    
IF 网络恢复:
    - 批量同步离线完成的任务
    - 重新计算 LXP（使用完整公式）
    - 如有差异，按更高分数结算（保护玩家）
```

### 5.2 跨日任务场景

| 场景 | 检测条件 | 处理策略 |
|------|---------|---------|
| 任务跨日完成 | start_time 和 complete_time 跨 UTC+8 00:00 | 归属到 start_time 日期，不影响新日常任务刷新 |
| 日常任务进行中刷新 | 任务在 00:00 前开始，00:00 后完成 | 任务继续可用，完成后计入前一天，新日常任务同时刷新 |
| 玩家时区变更 | device_timezone 变更 | 以 UTC+8 为准，保证全球玩家同步刷新 |

### 5.3 多设备登录场景

| 场景 | 检测条件 | 处理策略 | 数据一致性 |
|------|---------|---------|-----------|
| 同设备切换 | session_id 相同 | 正常继续任务进度 | 单设备无需同步 |
| 跨设备继续 | 新设备登录，有进行中的任务 | 询问"是否继续上次的任务？" | 从 Supabase 拉取最新进度 |
| 任务冲突 | 两台设备同时进行同一任务 | 后提交的覆盖先提交的（乐观锁） | 保留较高的 LXP 分数 |

### 5.4 异常数据场景

| 场景 | 检测条件 | 处理策略 |
|------|---------|---------|
| LXP > 100 | assessment-service 返回 > 100 | 钳制到 100，记录警告日志 |
| 星辉数异常 | 单次获得 > 5 星 | 拒绝并回滚，通知开发团队 |
| 负星辉数 | 计算结果为负数 | 归零处理，记录错误日志 |
| 任务状态冲突 | 客户端显示 completed，服务端显示 in_progress | 以服务端为准，客户端刷新 |
| 重复完成任务 | 同一个任务 ID 多次 complete 请求 | 幂等处理，返回首次完成的结果 |

### 5.5 防刷机制

| 场景 | 检测条件 | 处理策略 |
|------|---------|---------|
| 极速完成 | 任务完成时间 < 预估时间 × 0.3 | 标记为可疑，降低 LXP 50% |
| 高频重复 | 同一任务 1 小时内完成 > 2 次 | 第二次起只给 10% 奖励 |
| 作弊检测 | LXP 分布异常（如连续 10 次 100 分） | 触发人工审核，临时冻结奖励 |
| 脚本检测 | 请求间隔过于规律（如固定 1000ms） | 增加验证码挑战 |

### 5.6 降级策略

```
IF quest-service 不可用:
    - Godot 客户端切换到"简化任务模式"
    - 使用本地预定义任务序列
    - 评估仍发送到 assessment-service
    - 进度保存到本地，服务恢复后同步
    
IF content-service 不可用:
    - 使用客户端缓存的任务内容
    - 限制：只能玩已缓存的场景
    - 新场景显示"内容加载中，请稍后再试"
```

---

## 6. 依赖关系

### 6.1 上游依赖（输入来源）

| 系统 | 数据 | 用途 |
|------|------|------|
| content-service | 任务内容、期望答案、词汇列表 | 任务生成时的内容填充 |
| dialogue-service | 对话流程、NPC 配置 | 任务对话触发和流程控制 |
| assessment-service | LXP 分数、星级评估 | 任务完成时的评估结果 |
| voice-service | ASR 置信度、识别文本 | 任务回答的语音识别 |
| spirit-coach-service | 介入建议、提示语 | 困难时的 飞飞 介入 |

### 6.2 下游依赖（输出去向）

| 系统 | 数据 | 用途 |
|------|------|------|
| reward-service | 任务完成事件、星辉数 | 奖励计算和发放 |
| star-economy | 星辉累积、阈值状态 | 场景完成判断 |
| lxp-system | 任务完成时的 LXP | 玩家等级进度 |
| parent-dashboard | 任务完成统计、进度 | 家长报告展示 |
| Godot 客户端 | 任务列表、进度、状态 | UI 展示和交互 |

### 6.3 数据流向图

```
[Content Service] ──────┐
                          ▼
[Quest Service] ←── 生成任务内容
      │
      ├──→ [Dialogue Service] ──→ [NPC 对话]
      │
      ├──→ [Voice Service] ←── 玩家语音输入
      │       │
      │       ▼
      ├──→ [Assessment Service] ──→ LXP 评分
      │       │
      │       ▼
      ├──→ [Star Economy] ──→ 星辉累积
      │       │
      │       ▼
      └──→ [Reward Service] ──→ 奖励发放
              │
              ▼
      [Parent Dashboard] ──→ 进度报告
```

### 6.4 双向依赖检查

| 依赖系统 | 本系统提供 | 本系统消费 | 一致性检查 |
|----------|-----------|-----------|-----------|
| dialogue-service | quest_id, task_type | dialogue_flow | quest_id 必须在 dialogue 配置中存在 |
| assessment-service | quest_context | lxp_score, stars | assessment 需支持 quest-specific 评分 |
| reward-service | reward_payload | - | reward-service 需能解析 quest 类型奖励 |

---

## 7. 调节旋钮

### 7.1 可调节参数表

| 参数名 | 文件位置 | 默认值 | 建议范围 | 类别 | 说明 |
|--------|---------|--------|---------|------|------|
| `DAILY_QUEST_COUNT` | `assets/data/quest_config.json` | 3 | 2-5 | Gate | 每日日常任务数量 |
| `DAILY_QUEST_REFRESH_HOUR` | `assets/data/quest_config.json` | 0 | 0-23 | Gate | 日常任务刷新时间（UTC+8 小时） |
| `MAIN_QUESTS_PER_SCENE` | `assets/data/quest_config.json` | 3 | 2-6 | Gate | 每场景主线任务数 |
| `DDR_THRESHOLD_LOW` | `assets/data/quest_config.json` | 40 | 30-50 | Curve | 动态难度降级触发 LXP 阈值 |
| `DDR_THRESHOLD_HIGH` | `assets/data/quest_config.json` | 80 | 70-90 | Curve | 动态难度升级触发 LXP 阈值 |
| `FLOOR_STARS_MIN` | `assets/data/quest_config.json` | 2 | 1-3 | Gate | 保底机制最低星辉数（三层保底共用，§3.5） |
| `FLOOR_ATTEMPTS_TRIGGER` | `assets/data/quest_config.json` | 25 | 15-35 | Gate | 场景级保底触发回复数（场景内总回复数，§3.5） |
| `DAILY_LXP_BONUS` | ~~`quest_config.json`~~ | — | — | — | **已废弃**：日常任务 LXP 加成现由 §4.2 `calculateDailyQuestLXP` 公式统一管理 |
| `DAILY_STREAK_BONUS` | `assets/data/quest_config.json` | 0.1 | 0.05-0.2 | Curve | 日常任务连续完成加成系数（§4.2） |
| `QUEST_TIMEOUT_MIN` | `assets/data/quest_config.json` | 30 | 15-60 | Gate | 任务超时时间（分钟） |
| `SCENE_STAR_THRESHOLD` | `assets/data/quest_config.json` | 动态(15-25) | 10-30 | Curve | 场景 神器徽记 解锁动态阈值 |
| `MAX_ATTEMPTS_PER_QUEST` | `assets/data/quest_config.json` | -1 | -1,3-10 | Gate | 单任务最大尝试次数（-1=无限） |

### 7.2 任务类型难度配置

| 任务类型 | 基础难度 | LXP 权重 | 典型星辉范围 | 可调范围 |
|---------|---------|---------|-------------|---------|
| repeat | 2 | 1.0 | 1-2 | 难度 1-3 |
| listen | 3 | 1.0 | 1-3 | 难度 1-4 |
| describe | 5 | 1.0 | 2-4 | 难度 3-6 |
| converse | 7 | 1.0 | 2-4 | 难度 5-8 |

### 7.3 年级特定覆盖

| 年级 | 日常任务数 | DDR 阈值 | 保底星辉 | 说明 |
|------|-----------|---------|---------|------|
| 三年级 | 2 | 45/75 | 3 | 降低数量，提高保底 |
| 四年级 | 3（基准） | 40/80（基准） | 2（基准） | 基准配置 |
| 五年级 | 4 | 35/85 | 2 | 增加数量，降低阈值 |

### 7.4 快速调优建议

**如果玩家反馈"任务太少"：**
1. DAILY_QUEST_COUNT: 3 → 4
2. MAIN_QUESTS_PER_SCENE: 3 → 4

**如果玩家反馈"任务太难"：**
1. DDR_THRESHOLD_LOW: 40 → 45（更早触发降级）
2. FLOOR_STARS_MIN: 2 → 3（更高保底）
3. 减少 describe/converse 任务比例

**如果玩家反馈"奖励不够"：**
1. DAILY_STREAK_BONUS: 0.1 → 0.15（§4.2 连续完成加成）
2. SCENE_STAR_THRESHOLD: 20 → 18（更容易解锁 神器徽记）
3. 在 §4.2 公式中提升 questIndex 系数（0.1 → 0.15）

**如果数据分析师发现任务完成率过低：**
1. 检查 DDR_THRESHOLD_LOW 是否过高
2. 检查 FLOOR_ATTEMPTS_TRIGGER 是否过低
3. 考虑降低 describe/converse 的难度系数

---

## 8. 接受标准

### 8.1 功能测试

- [ ] GET /api/quests/main/:playerId/:sceneId 返回正确的任务列表
- [ ] GET /api/quests/daily/:playerId 返回今日 3 个日常任务
- [ ] POST /api/quests/complete/:questId 正确计算并发放奖励
- [ ] 任务状态机正确流转（locked → available → in_progress → completed）
- [ ] 基本 DDR 在最近 3 次任务 avgLXP < 40 时正确触发降级（§3.2）
- [ ] 干预级 DDR 在 struggle_score >= 0.67 时正确触发 飞飞 介入 + 保底（§3.2）
- [ ] 场景级保底在场景内总回复数 > 25 次 AND 当前星辉 < threshold 时正确激活（§3.5）
- [ ] 单回复保底在第 3 次尝试 raw_lxp < 40 时正确生效（lxp-system.md）
- [ ] 日常任务在 UTC+8 00:00 正确刷新
- [ ] 网络断开后本地缓存，恢复后正确同步

### 8.2 边界测试

- [ ] 跨日任务正确归属到开始日期
- [ ] 多设备同时操作同一任务时数据一致性正确
- [ ] LXP > 100 时正确钳制到 100
- [ ] 任务完成时间 < 预估 30% 时触发防刷机制
- [ ] quest-service 不可用时正确降级到离线模式
- [ ] 场景内总回复数 > 25 次且星辉不足 threshold 时触发场景级保底解锁（§3.5）

### 8.3 性能测试

- [ ] GET /daily API 响应时间 < 100ms（P95）
- [ ] GET /main API 响应时间 < 150ms（P95）
- [ ] 并发 100 个任务完成请求，数据无竞争
- [ ] 任务进度保存成功率 >= 99.9%
- [ ] 日常任务刷新操作 < 500ms（含 3 个任务的生成）

### 8.4 集成测试

- [ ] quest-service → assessment-service → reward-service 链路完整
- [ ] 任务完成事件正确发送到 parent-dashboard
- [ ] 飞飞 介入事件正确发送到 spirit-coach-service
- [ ] Godot 客户端正确显示任务列表和进度
- [ ] 场景完成时正确触发 神器徽记 解锁事件

### 8.5 体验测试（儿童用户）

- [ ] 6-10 岁测试玩家理解"主线任务"和"日常任务"的区别
- [ ] 测试玩家在任务困难时接受 飞飞 的辅助提示
- [ ] 测试玩家愿意完成全部 3 个日常任务以获得额外奖励
- [ ] 测试玩家在获得"Daily Star"徽章时感到成就感
- [ ] 测试玩家理解任务进度条和星辉累积目标

### 8.6 数据一致性验证

```
测试场景: MistyBay 场景完整流程（验证星辉计算链路一致性）
输入:
  - 玩家: 四年级水平
  - 任务: 3 个主线任务（repeat + listen + describe）
  - 表现: 平均 2.5 星/回复（由 star-economy §4.1 LXP→星辉映射得出）
  - 预估回复数: 6-8 次（含重试，基于 §4.5 estimateQuestTime）

预期输出:
  - 完成时间: 8-12 分钟
  - 获得星辉: 15-20 星（2.5 星/回复 × 6-8 回复）
  - 获得 LXP: 150-250
  - 获得金币: 75-100
  - 神器徽记 解锁: 是（如果星辉 >= 动态阈值，参考 star-economy §4.1 `calculate_artifact_mark_threshold`）
```

---

## 附录 A: 任务类型详细设计

### A.1 口语重复任务 (Repeat)

**任务流程**：
```
1. NPC 播放示范音频: "Hello!"
2. 飞飞 提示: "跟我一起说: Hello!"
3. 玩家语音输入
4. ASR 转录 → LXP 评估
5. 反馈:
   - 3-5 星: "说得真好！"
   - 1-2 星: "没关系，再来一次"
```

**期望答案示例**：
- 输入: "Hello" / "Hi" / "Hey"
- 评估: 关键词匹配（"Hello" 或同义表达）

### A.2 听力理解任务 (Listen)

**任务流程**：
```
1. NPC 播放音频（不显示文字）
2. 屏幕显示 3 个图片选项
3. 玩家选择正确答案（点击或语音回答）
4. 正确 → 3 星 + 金币
5. 错误 → 飞飞 提示"再听一遍"（可重试）
```

**示例**：
- 音频: "The flower is red."
- 选项: [红色花图片] [蓝色花图片] [黄色花图片]
- 答案: 红色花图片

### A.3 图片描述任务 (Describe)

**任务流程**：
```
1. 屏幕显示图片（如：蓝色小鸟站在树上）
2. 飞飞 提示: "看一看，这个是什么颜色？"
3. 玩家语音描述
4. ASR 转录 → LXP 评估（关键词检测）
5. 反馈基于描述完整性
```

**评估关键词**：
- 基础分: 说出 "bird" → 2 星
- 完整分: 说出 "blue bird" 或 "bird on tree" → 3 星
- 扩展分: 说出 "The blue bird is on the tree." → 4-5 星

### A.4 自由对话任务 (Converse)

**任务流程**：
```
1. 飞飞 发起对话: "What's your favorite color?"
2. 玩家自由回答（无固定答案）
3. LLM 评估回答相关性和语法
4. 多轮对话（3-5 轮）
5. 基于整体对话质量评分
```

**评估维度**：
- 相关性: 回答是否与问题相关
- 语法: 基本语法正确性
- 流利度: 语速和停顿
- 词汇: 使用本课词汇

---

## 附录 B: 与现有系统的数值对齐

### B.1 与 star-economy.md 对齐

| 来源 | 参数 | Quest System 使用 | 一致性 |
|------|------|------------------|--------|
| star-economy.md | 动态阈值公式 calculate_artifact_mark_threshold() | SCENE_STAR_THRESHOLD = 动态(15-25) | ✓ 一致（使用 star-economy 动态阈值，非硬编码） |
| star-economy.md | 口语重复 1 星 | repeat 任务预期 1 星 | ✓ 一致 |
| star-economy.md | 听力理解 1 星 | listen 任务预期 1 星 | ✓ 一致 |
| star-economy.md | 图片描述 2 星 | describe 任务预期 2 星 | ✓ 一致 |
| star-economy.md | 自由对话 2-3 星 | converse 任务预期 2-3 星 | ✓ 一致 |

### B.2 与 lxp-system.md 对齐

| 来源 | 参数 | Quest System 使用 | 一致性 |
|------|------|------------------|--------|
| lxp-system.md | ACCURACY_WEIGHT = 0.4 | 任务评估使用相同权重 | ✓ 一致 |
| lxp-system.md | FLUENCY_WEIGHT = 0.3 | 任务评估使用相同权重 | ✓ 一致 |
| lxp-system.md | VOCABULARY_WEIGHT = 0.3 | 任务评估使用相同权重 | ✓ 一致 |
| lxp-system.md | WPM_TARGET = 60 (四年级ESL) | 任务时间估算使用 | ✓ 一致（从80调整为60，ESL标准） |

### B.3 与 core-loop.md 对齐

| 来源 | 参数 | Quest System 使用 | 一致性 |
|------|------|------------------|--------|
| core-loop.md | 每场景 3-4 任务 | MAIN_QUESTS_PER_SCENE = 3 | ✓ 一致 |
| core-loop.md | 每会话 3 日常任务 | DAILY_QUEST_COUNT = 3 | ✓ 一致 |
| core-loop.md | 动态阈值解锁 神器徽记 | SCENE_STAR_THRESHOLD = 动态(15-25) | ✓ 一致（动态阈值机制） |

---

## 下一步

1. `/design-review design/gdd/quest-system.md` — 审查此 GDD
2. `/consistency-check` — 验证与其他 GDD 的数值一致性
3. 实现 quest-service API 接口
4. 配置 Godot 客户端任务 UI
5. 集成日常任务自动刷新机制
