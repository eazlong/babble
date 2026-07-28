# Reward System

**系统名称**: Reward System (奖励系统)  
**版本**: 1.0 (Complete)  
**日期**: 2026-07-07  
**所属游戏**: LinguaQuest RPG (babble)  
**负责服务**: reward-service  
**依赖系统**: 无（基础系统）  
**被依赖**: Core Loop, Star Economy  
**状态**: ✅ Designed (Pending Review)  

---

## 1. Overview

**Reward System**是 LinguaQuest RPG 的进度奖励基础设施，管理玩家在游戏中获得的所有奖励类型（星辉、徽章、金币、装饰品、皮肤）的获取、存储和消费。系统同时提供**数据层**（奖励定义、库存管理、消费逻辑）和**玩家体验层**（奖励展示、解锁动画、收集满足感）。

**系统角色：**
- **数据层**: 定义所有奖励类型（星辉/徽章/金币/装饰/皮肤）的属性、获取条件和消费规则
- **进度层**: 将玩家表现（LXP分数、任务完成）转化为可见的奖励积累
- **动机层**: 通过奖励解锁新内容（场景、装饰、飞飞皮肤）提供长期动力
- **经济层**: 管理星辉作为永久货币的获取与消费循环

**核心职责：**
1. 定义奖励物品的元数据（类型、稀有度、获取方式、消费价格）
2. 追踪玩家的奖励库存（星辉、金币、已解锁物品）
3. 处理奖励获取逻辑（任务完成、神器徽记解锁、每日登录）
4. 处理奖励消费逻辑（商店兑换、装饰装备）
5. 提供奖励展示接口（解锁动画、库存查询）

**与其他系统的关系：**
- **上游**: 从 LXP Assessment 接收表现评分，从 Quest System 接收任务完成事件
- **下游**: 向 Star Economy 提供星辉库存和消费接口，向 Core Loop 提供奖励展示触发

---

## 2. Player Fantasy

**玩家应该感觉**："我在迷雾岛收集珍贵的宝物，每一次努力都让我离成为强大言灵师更近一步"

**核心情感体验：**
- **收集满足感**：看着星辉、徽章、装饰品逐渐填满收藏册，产生"收集癖"的满足
- **解锁成就感**：当累积足够的星辉解锁新场景或飞飞皮肤时，感受到"我的努力有回报"
- **拥有感**：装备自己收集的装饰品，在迷雾岛中展示个人风格
- **进步可视化**：通过奖励数量直观看到自己的成长轨迹

**玩家时刻锚点：**
1. **第一次神器徽记解锁**：累积10颗星辉后，NPC宣布"你获得了Forest 神器徽记！"，星辉转化为永久奖励，解锁新装饰——这是玩家第一次感受到"语言即钥匙"的力量
2. **商店首次消费**：用攒下的星辉在商店换取第一个飞飞皮肤，体验到"我的选择让游戏世界与众不同"
3. **收藏册填满**：打开收藏界面，看到所有已解锁的徽章、装饰品排列整齐，产生"我做到了"的自豪

**与游戏支柱的对齐：**
- **语言即钥匙**：奖励（星辉、徽章、装饰）只能通过说英语获得，强化"英语是打开迷雾岛的钥匙"
- **无失败惩罚**：奖励获取是渐进的，没有"错过就失去"的焦虑，玩家可以按自己的节奏收集
- **陪伴式学习**：飞飞在奖励解锁时表达祝贺，强化陪伴感

**参考游戏的情感设计：**
- **Animal Crossing**：收集家具装饰房屋的快乐，每次登录看到自己的风格
- **Pokémon**：收集徽章的成就感，徽章墙展示的骄傲
- **Duolingo**：连续打卡的streak机制，但去除竞争压力，保留进度可视化

---

## 3. Detailed Design

### 3.1 Core Rules

**奖励类型定义：**

| 类型 | 属性 | 获取方式 | 存储位置 | 可消费 |
|------|------|----------|----------|--------|
| **星辉** (Star) | 数量（整数） | 任务完成（1-5星/次）、神器徽记解锁转化 | 玩家账户（永久） | ✅ 商店兑换 |
| **徽章** (神器徽记) | 类型（Forest/Library/Garden）、稀有度 | 场景星辉达到阈值 | 收藏册 | ❌ 收藏品 |
| **金币** (Coin) | 数量（整数） | 神器徽记解锁转化、特殊成就 | 玩家账户（永久） | ✅ 特殊物品 |
| **装饰品** (Decoration) | ID、类型、稀有度、价格 | 商店购买、任务奖励 | 背包（已解锁列表） | ✅ 装备到场景 |
| **皮肤** (Skin) | ID、类型（飞飞/NPC）、价格 | 商店购买、成就解锁 | 背包（已解锁列表） | ✅ 装备到角色 |

**核心规则：**

1. **星辉获取**：每次任务完成获得1-5颗星（由LXP Assessment的评分决定），星辉立即加入玩家账户
2. **神器徽记解锁**：当场景累积星辉达到阈值（默认10颗）时，触发神器徽记解锁流程：
   - 播放神器徽记解锁动画（30秒）
   - 将threshold颗星辉转化为永久奖励：LXP = threshold×10, 金币 = threshold×5
   - 将神器徽记加入收藏册
   - 解锁该场景专属装饰品/皮肤（免费赠送1件）
3. **商店兑换**：玩家可在商店使用星辉兑换装饰品/皮肤，兑换后物品加入背包
4. **装备系统**：玩家可从背包选择装饰品装备到场景，选择皮肤装备到飞飞/NPC，装备后立即生效
5. **永久保留**：所有奖励（星辉、金币、已解锁物品）跨会话永久保留，不会因失败或超时丢失
6. **保底机制**：连续3次任务失败后，下次任务必定获得3星（即使表现较差），防止挫败感

### 3.2 States and Transitions

**玩家奖励状态：**

```typescript
interface PlayerRewardState {
  user_id: string
  
  // 货币
  stars: number           // 当前星辉数量
  coins: number           // 当前金币数量
  
  // 收藏品
  artifact_marks: 神器徽记[]         // 已解锁的徽章列表
  unlocked_items: string[] // 已解锁的装饰品/皮肤ID列表
  
  // 装备
  equipped_decorations: {
    scene_id: string
    decoration_id: string
  }[]
  equipped_spark_skin: string | null
  
  // 统计
  total_stars_earned: number    // 历史总获得星辉
  total_stars_spent: number     // 历史总消费星辉
  
  // 保底
  consecutive_failures: number  // 连续失败次数
}

interface 神器徽记 {
  artifact_mark_id: string        // e.g. "forest_artifact_mark"
  scene_id: string        // e.g. "spirit_forest"
  unlocked_at: number     // timestamp
  threshold_used: number  // 解锁时消耗的星辉数
}
```

**状态转换：**

| 触发事件 | 状态变化 |
|----------|----------|
| 任务完成（获得N星） | `stars += N`, `total_stars_earned += N`, `consecutive_failures = 0` |
| 任务失败 | `consecutive_failures += 1` |
| 场景星辉 >= threshold | 触发神器徽记解锁 → `stars -= threshold`, `artifact_marks.push(new 神器徽记)`, `coins += threshold*5`, `unlocked_items.push(scene_exclusive_item)` |
| 商店兑换（花费M星） | `stars -= M`, `total_stars_spent += M`, `unlocked_items.push(item_id)` |
| 装备装饰品 | `equipped_decorations[scene_id] = decoration_id` |
| 装备皮肤 | `equipped_spark_skin = skin_id` |

### 3.3 Interactions with Other Systems

**上游依赖（输入）：**

| 来源系统 | 事件/数据 | Reward System响应 |
|----------|-----------|-------------------|
| LXP Assessment | `task_completed { stars_earned: 1-5 }` | 增加玩家星辉，更新统计 |
| Quest System | `quest_completed { quest_id, scene_id }` | 检查场景星辉是否达到神器徽记阈值 |
| Quest System | `quest_failed { quest_id }` | 增加consecutive_failures计数 |

**下游依赖（输出）：**

| 目标系统 | 接口 | 用途 |
|----------|------|------|
| Star Economy | `get_player_state(user_id) → PlayerRewardState` | 查询星辉库存、已解锁物品 |
| Star Economy | `spend_stars(user_id, amount, item_id) → success/fail` | 商店兑换 |
| Core Loop | `on_artifact_mark_unlocked(artifact_mark) → trigger_animation()` | 触发神器徽记解锁动画 |
| Core Loop | `on_item_unlocked(item) → trigger_popup()` | 触发物品解锁提示 |
| Client | `get_equipped_items(user_id) → equipped_list` | 渲染装备的装饰品/皮肤 |

**数据所有权：**
- **Reward System拥有**：PlayerRewardState（星辉、金币、徽章、已解锁物品、装备）
- **LXP Assessment拥有**：任务评分逻辑（决定获得几颗星）
- **Quest System拥有**：任务状态（完成/失败）、场景进度
- **Client拥有**：渲染逻辑（如何显示装备的装饰品）

---

## 4. Formulas

### 4.1 Effective Stars per Task

**星辉获取公式**（统一保底逻辑，替代分散在3个文档的保底机制）：

$$stars_{effective} = \max(stars_{lookup}(LXP), stars_{floor})$$

$$stars_{floor} = \begin{cases} 3 & \text{if } attemptCount \geq 5 \\ 2 & \text{if } attemptCount \geq 3 \\ 1 & \text{otherwise} \end{cases}$$

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| LXP分数 | LXP | float | 0-100 | assessment-service输出 |
| 查找表星辉 | stars_lookup | int | 1-5 | 0-39→1, 40-59→2, 60-74→3, 75-89→4, 90-100→5 |
| 尝试次数 | attemptCount | int | 1-5 | 当前任务尝试次数 |
| 保底星辉 | stars_floor | int | 1-3 | 保底下限 |
| 有效星辉 | stars_effective | int | 1-5 | 最终获得星辉数 |

**Output Range:** 1-5 整数

**Example:**
- LXP=35, attemptCount=3 → stars_lookup=1, floor=2 → **stars=2**
- LXP=55, attemptCount=1 → stars_lookup=2, floor=1 → **stars=2**
- LXP=25, attemptCount=5 → stars_lookup=1, floor=3 → **stars=3**

**Note:** 此公式统一了star-economy、quest-system、lxp-system中分散的保底逻辑。所有保底判断由此公式统一管理。

---

### 4.2 神器徽记 Threshold (Dynamic)

**神器徽记解锁阈值公式**（根据场景难度和玩家表现动态调整）：

$$threshold = clamp(15 + D_{scene} + \lfloor(\bar{s} - 2.0) \times 3\rfloor, 10, 25)$$

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 基础阈值 | base | int | 固定=15 | 所有场景的基础阈值 |
| 场景难度 | D_scene | int | 0/3/5 | MistyBay=0, WordSpiritLibrary=3, LanternCourtyard=5 |
| 平均星辉 | s̄ | float | 1.0-5.0 | 玩家最近10次回复的平均星辉数 |
| 调整系数 | k | float | 固定=3 | 玩家调整灵敏度 |
| 最小阈值 | T_min | int | 固定=10 | 阈值下限 |
| 最大阈值 | T_max | int | 固定=25 | 阈值上限 |
| 最终阈值 | threshold | int | 10-25 | 神器徽记解锁所需星辉数 |

**Output Range:** 10-25 整数

**Example:**

| 玩家 | s̄ | MistyBay(D=0) | WordSpiritLibrary(D=3) | LanternCourtyard(D=5) |
|------|----|--------------------|--------------------|---------------------|
| 困难 | 1.2 | 13 | 15 | 17 |
| 中等 | 2.0 | 15 | 18 | 20 |
| 优秀 | 3.5 | 19 | 22 | 24 |

---

### 4.3 Shop Pricing (Fixed by Rarity)

**商店定价表**（按稀有度固定价格）：

| Rarity | Price (stars) | Example Items |
|--------|---------------|---------------|
| common | 5 | 场景小装饰（言灵蘑菇、小花） |
| uncommon | 10 | 场景装饰、每日宝箱 |
| rare | 15 | 飞飞基础皮肤 |
| epic | 25 | 飞飞高级皮肤 |
| legendary | 40 | 传说级外观（需CEFR升级解锁购买资格） |

**定价平衡验证：**

| 玩家水平 | 日均星辉收入 | 购买common(5) | 购买rare(15) | 购买epic(25) |
|---------|------------|---------------|--------------|--------------|
| 困难(12星/天) | 12 | 0.4天 | 1.3天 | 2.1天 |
| 中等(20星/天) | 20 | 0.3天 | 0.8天 | 1.3天 |
| 优秀(20星/天) | 20 | 0.3天 | 0.8天 | 1.3天 |

**Note:** 中等和优秀玩家收入相近（20星/天），因为优秀玩家阈值更高但每次收益更多。商店消费和神器徽记进度解耦。

---

### 4.4 神器徽记 Unlock Rewards

**神器徽记解锁奖励公式**（基础奖励固定，超额部分递减）：

$$R_{LXP} = 15 \times 10 + \max(0, s_{scene} - threshold) \times 5$$

$$R_{coin} = 15 \times 5 = 75$$

$$R_{star\_wallet} = \max(0, s_{scene} - threshold)$$

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 基础阈值 | T_base | int | 固定=15 | 保证所有玩家基础奖励一致 |
| LXP转化系数 | r_LXP | int | 固定=10 | 基础LXP转化率 |
| 超额转化系数 | r_excess | int | 固定=5 | 超额星辉LXP转化率（低于基础，防刷星） |
| 金币转化系数 | r_coin | int | 固定=5 | 金币转化率 |
| 场景星辉 | s_scene | int | threshold-100 | 场景内实际累积星辉数 |
| 阈值 | threshold | int | 10-25 | 动态阈值（公式4.2） |
| LXP奖励 | R_LXP | int | 150+ | 神器徽记解锁奖励LXP |
| 金币奖励 | R_coin | int | 75 | 神器徽记解锁奖励金币（固定） |
| 钱包星辉 | R_star_wallet | int | 0-75 | 超额星辉转入钱包供商店消费 |

**Output Range:**
- R_LXP: 150+（基础150 + 超额每星5 LXP）
- R_coin: 固定75
- R_star_wallet: 0-75

**Example:**
- 中等玩家 WordSpiritLibrary: threshold=18, s_scene=22
  - R_LXP = 15×10 + (22-18)×5 = 150 + 20 = **170 LXP**
  - R_coin = **75 金币**
  - R_star_wallet = 22-18 = **4 星**

- 困难玩家 MistyBay: threshold=13, s_scene=15
  - R_LXP = 15×10 + (15-13)×5 = 150 + 10 = **160 LXP**
  - R_coin = **75 金币**
  - R_star_wallet = 15-13 = **2 星**

**Note:** 基础LXP固定（T_base=15），不随动态阈值变化，确保所有玩家解锁神器徽记获得的基础奖励相同（150 LXP）。超额部分按较低比率（5 vs 10）额外奖励，边际递减防止刷星。

---

## 5. Edge Cases

**如果玩家星辉为0且尝试购买物品**：拒绝交易，显示"星辉不足"提示，不扣除任何费用。客户端应在点击购买前检查余额并禁用按钮。

**如果玩家在神器徽记解锁动画期间断开连接**：
- 服务端已完成状态更新（stars扣除、神器徽记添加、奖励发放）
- 客户端重连后，通过`get_player_state`接口获取最新状态
- 如果动画未播放完成，客户端检测到新神器徽记但未见过动画 → 重播神器徽记解锁动画（30秒）
- 如果动画已标记为已观看 → 跳过动画，直接显示新状态

**如果同一玩家同时触发两个场景的神器徽记解锁**：
- 按场景ID字母顺序串行处理（MistyBay → WordSpiritLibrary → LanternCourtyard）
- 第一个神器徽记解锁完成后，检查第二个场景是否也达到阈值
- 每个神器徽记解锁独立播放动画和奖励
- 不会同时播放两个动画（避免UI混乱）

**如果玩家通过故意说错来降低平均星辉s̄，从而降低神器徽记阈值**：
- 公式设计已考虑：s̄降低 → threshold降低 → 但每次获得星辉也减少
- 实际效果：困难玩家阈值13，每次保底2星 → 需7次回复
- 中等玩家阈值18，每次2.5星 → 需8次回复
- **结论**：故意说错不会显著加快神器徽记解锁速度（7次 vs 8次），且LXP获得更少
- 额外防护：如果`consecutive_failures ≥ 5`触发3星保底，进一步降低"故意失败"的收益

**如果玩家星辉达到场景硬上限（100星）但未解锁神器徽记**：
- 不应发生：阈值最大25，100星远超阈值
- 如果发生（数据异常）：强制触发神器徽记解锁，按实际threshold计算奖励
- 记录warning日志用于排查

**如果商店物品库存为0（所有物品都已解锁）**：
- 商店显示"所有物品已解锁"
- 提供"每日宝箱"作为唯一可购买项（10星/次，随机奖励）
- 每日宝箱每日限购1次

**如果玩家装备了已删除/下架的装饰品**：
- 装饰品从背包移除时，自动卸载装备
- 如果场景正在渲染该装饰品，立即切换为默认外观
- 向玩家发送通知："该装饰品已下架，已从装备中移除"

**如果玩家连续多次购买同一物品**：
- 同一物品只能购买一次（`unlocked_items`是集合，不允许重复）
- 如果尝试购买已拥有的物品，拒绝交易并提示"已拥有此物品"

---

## 6. Dependencies

**上游依赖（Reward System需要）：**

| 系统 | 接口 | 数据流 | 依赖类型 |
|------|------|--------|----------|
| LXP Assessment | `task_completed { stars_earned: 1-5 }` | 任务完成事件，携带星辉数 | 硬依赖（必须） |
| Quest System | `quest_completed { quest_id, scene_id }` | 任务完成事件 | 硬依赖（必须） |
| Quest System | `quest_failed { quest_id }` | 任务失败事件 | 硬依赖（必须） |
| Supabase | `player_reward_state` 表 | 玩家奖励状态持久化 | 硬依赖（必须） |

**下游依赖（需要Reward System）：**

| 系统 | 接口 | 数据流 | 依赖类型 |
|------|------|--------|----------|
| Star Economy | `get_player_state(user_id)` | 查询星辉/金币/物品库存 | 硬依赖 |
| Star Economy | `spend_stars(user_id, amount, item_id)` | 商店兑换 | 硬依赖 |
| Star Economy | `equip_item(user_id, item_id, slot)` | 装备物品 | 硬依赖 |
| Core Loop | `on_artifact_mark_unlocked(artifact_mark)` | 神器徽记解锁通知 | 软依赖（可降级） |
| Core Loop | `on_item_unlocked(item)` | 物品解锁通知 | 软依赖 |
| Client | `get_equipped_items(user_id)` | 查询装备列表 | 硬依赖 |

**数据所有权：**
- **Reward System拥有**：`PlayerRewardState`（星辉、金币、徽章、已解锁物品、装备）
- **LXP Assessment拥有**：任务评分逻辑
- **Quest System拥有**：任务状态、场景进度
- **Client拥有**：渲染逻辑

**接口契约：**
- 所有接口使用JSON格式
- 错误响应：`{ error: string, code: number }`
- 成功响应：根据接口定义返回具体数据结构

---

## 7. Tuning Knobs

| Knob | Default | Range | Category | Description |
|------|---------|-------|----------|-------------|
| `artifact_mark_base_threshold` | 15 | 10-20 | Curve | 神器徽记解锁基础阈值 |
| `artifact_mark_min_threshold` | 10 | 5-15 | Gate | 神器徽记阈值下限 |
| `artifact_mark_max_threshold` | 25 | 20-30 | Gate | 神器徽记阈值上限 |
| `artifact_mark_lxp_multiplier` | 10 | 5-20 | Curve | 神器徽记解锁LXP转化系数 |
| `artifact_mark_coin_multiplier` | 5 | 2-10 | Curve | 神器徽记解锁金币转化系数 |
| `artifact_mark_excess_lxp_rate` | 5 | 2-10 | Curve | 超额星辉LXP转化率 |
| `shop_price_common` | 5 | 3-10 | Feel | 普通物品价格 |
| `shop_price_uncommon` | 10 | 7-15 | Feel | 稀有物品价格 |
| `shop_price_rare` | 15 | 12-20 | Feel | 珍稀物品价格 |
| `shop_price_epic` | 25 | 20-35 | Feel | 史诗物品价格 |
| `shop_price_legendary` | 40 | 30-50 | Feel | 传说物品价格 |
| `daily_chest_price` | 10 | 5-20 | Feel | 每日宝箱价格 |
| `floor_star_threshold_3` | 3 | 2-5 | Gate | 连续失败几次触发3星保底 |
| `floor_star_threshold_2` | 5 | 3-7 | Gate | 连续失败几次触发2星保底 |
| `scene_difficulty_forest` | 0 | 0-5 | Curve | MistyBay难度系数 |
| `scene_difficulty_library` | 3 | 0-5 | Curve | WordSpiritLibrary难度系数 |
| `scene_difficulty_garden` | 5 | 0-5 | Curve | LanternCourtyard难度系数 |

**Knob交互说明：**
- `artifact_mark_base_threshold` 与 `artifact_mark_lxp_multiplier` 联动：提高base会增加解锁难度，但也会增加LXP奖励
- `shop_price_*` 系列需要根据玩家日均收入平衡调整
- `floor_star_threshold_*` 影响困难玩家体验，需要谨慎调整

---

## 8. Visual/Audio Requirements

**神器徽记解锁动画（30秒，不可跳过）：**
- **视觉**：
  - 屏幕中央显示神器徽记图标，从模糊→清晰（0-5秒）
  - 神器徽记周围星辉旋转汇聚（5-10秒）
  - 神器徽记发光+粒子特效（10-15秒）
  - 显示奖励明细：LXP +150, 金币 +75, 装饰品 +1（15-25秒）
  - 飞飞祝贺动画（25-30秒）
- **音频**：
  - 解锁音效（清脆的言灵音效）
  - NPC祝贺语音（"Congratulations! You earned the Forest 神器徽记!"）
  - 背景音乐转为欢快旋律

**星辉获取反馈（即时，1-2秒）：**
- **视觉**：
  - 任务完成时，屏幕上方显示星辉图标 + 数量（+3）
  - 星辉飞入右上角计数器（动画0.5秒）
  - 计数器数字跳动更新
- **音频**：
  - 星辉获得音效（根据数量：1星=单音, 3星=和弦, 5星=华丽音效）

**商店兑换反馈（即时，2-3秒）：**
- **视觉**：
  - 点击购买 → 物品图标高亮
  - 星辉扣除动画（从计数器飞出）
  - 物品飞入背包（动画1秒）
  - 显示"购买成功"提示
- **音频**：
  - 购买成功音效
  - 星辉扣除音效

**装备反馈（即时，1秒）：**
- **视觉**：
  - 装备后场景/NPC立即显示新装饰品/皮肤
  - 装备按钮变为"已装备"状态
- **音频**：
  - 装备音效（轻微的言灵音效）

**金币获取反馈（与神器徽记解锁一起）：**
- 金币图标与LXP一起显示
- 金币飞入计数器

---

## 9. UI Requirements

**右上角HUD（常驻显示）：**
- 星辉计数器：图标 + 数字（如 ⭐ 125）
- 金币计数器：图标 + 数字（如 🪙 75）
- 点击星辉/金币 → 打开商店/背包界面

**商店界面（全屏弹窗）：**
- 顶部：当前星辉余额
- 分类标签：装饰品 / 飞飞皮肤 / NPC皮肤 / 每日宝箱
- 物品网格：图标 + 名称 + 价格
- 已拥有物品：灰色显示 + "已拥有"标签
- 购买按钮：点击后确认弹窗
- 关闭按钮：右上角X

**背包界面（全屏弹窗）：**
- 分类标签：装饰品 / 飞飞皮肤 / NPC皮肤
- 物品网格：图标 + 名称 + "装备"按钮
- 已装备物品：绿色边框 + "已装备"标签
- 装备按钮：点击后立即生效
- 关闭按钮：右上角X

**神器徽记收藏册界面（全屏弹窗）：**
- 3个场景标签：MistyBay / WordSpiritLibrary / LanternCourtyard
- 每个场景显示：
  - 神器徽记图标（未解锁=灰色剪影，已解锁=彩色）
  - 进度条：当前星辉 / 阈值（如 12/18）
  - 解锁时间（已解锁时显示）
- 点击神器徽记 → 显示解锁动画回放

**神器徽记解锁弹窗（全屏，30秒）：**
- 自动播放，不可跳过
- 显示神器徽记图标、奖励明细、飞飞祝贺
- 30秒后自动关闭，或点击"继续"按钮关闭

**每日宝箱弹窗（全屏）：**
- 显示宝箱图标
- 价格：10星
- "开启"按钮（星辉不足时禁用）
- 开启后显示随机奖励
- 每日限购提示："今日已购买"或"剩余1次"

---

## 10. Acceptance Criteria

**AC1: 星辉获取**
- **GIVEN** 玩家完成一个任务，LXP评分为75
- **WHEN** LXP Assessment发送 `task_completed { stars_earned: 4 }`
- **THEN** 玩家星辉余额增加4，`total_stars_earned` 增加4，`consecutive_failures` 重置为0

**AC2: 保底星辉（3次失败）**
- **GIVEN** 玩家连续3次任务获得1星
- **WHEN** 第4次任务完成，LXP评分为30（正常应得1星）
- **THEN** 玩家获得2星（保底激活）

**AC3: 保底星辉（5次失败）**
- **GIVEN** 玩家连续5次任务获得1星
- **WHEN** 第6次任务完成，LXP评分为25（正常应得1星）
- **THEN** 玩家获得3星（高级保底激活）

**AC4: 神器徽记解锁**
- **GIVEN** 玩家在MistyBay累积15星，阈值为13
- **WHEN** Quest System发送 `quest_completed { scene_id: "spirit_forest" }`
- **THEN** 触发神器徽记解锁：星辉扣除13，神器徽记加入收藏册，获得160 LXP，获得75金币，获得2颗超额星辉进入钱包，播放神器徽记解锁动画

**AC5: 商店购买**
- **GIVEN** 玩家有50星，未拥有"言灵蘑菇"（5星）
- **WHEN** 玩家在商店点击购买"言灵蘑菇"
- **THEN** 星辉余额减少5（变为45），"言灵蘑菇"加入背包，显示"购买成功"

**AC6: 星辉不足**
- **GIVEN** 玩家有3星，尝试购买10星物品
- **WHEN** 玩家点击购买
- **THEN** 交易拒绝，显示"星辉不足"提示，星辉余额不变

**AC7: 装备装饰品**
- **GIVEN** 玩家背包中有"言灵蘑菇"装饰品
- **WHEN** 玩家在背包点击"装备"按钮
- **THEN** 装饰品立即显示在MistyBay场景中，`equipped_decorations` 更新

**AC8: 断线重连**
- **GIVEN** 玩家在神器徽记解锁动画播放到15秒时断开连接
- **WHEN** 玩家重连
- **THEN** 客户端检测到新神器徽记未播放过动画，重播完整的30秒神器徽记解锁动画

**AC9: 重复购买**
- **GIVEN** 玩家已拥有"言灵蘑菇"
- **WHEN** 玩家再次尝试购买"言灵蘑菇"
- **THEN** 交易拒绝，显示"已拥有此物品"

**AC10: 动态阈值**
- **GIVEN** 玩家最近10次平均星辉为2.0
- **WHEN** 进入WordSpiritLibrary场景（D_scene=3）
- **THEN** 神器徽记阈值计算为：clamp(15 + 3 + 0, 10, 25) = 18

**AC11: 超额星辉LXP递减**
- **GIVEN** 玩家神器徽记阈值18，实际累积25星
- **WHEN** 神器徽记解锁触发
- **THEN** LXP奖励 = 150（基础）+ (25-18)×5 = 185，而非150 + 7×10 = 220

**AC12: 并发神器徽记解锁**
- **GIVEN** 玩家MistyBay和WordSpiritLibrary都达到阈值
- **WHEN** 两个场景的神器徽记解锁条件同时满足
- **THEN** 按字母顺序串行处理：先MistyBay，完成后处理WordSpiritLibrary

---

## 11. Open Questions

| Question | Owner | Target Date | Status |
|----------|-------|-------------|--------|
| 金币的具体消费途径（消耗品种类：提示卡、跳过卡？）| Game Designer | Phase 2 | Open |
| 每日宝箱的随机奖励表（概率分布？）| Economy Designer | Phase 2 | Open |
| 传说级物品的CEFR升级条件（具体阈值？）| Game Designer | Phase 2 | Open |
| 每周限定商品的刷新逻辑和商品池 | Game Designer | Phase 2 | Open |
| 装饰品是否可以交易/赠送（社交功能）| Product | Phase 3 | Open |
| 神器徽记解锁动画是否可以跳过（30秒是否太长）| UX Designer | Phase 1 | Open |
| 保底机制是否与spirit-coach的DDR冲突（需要协调）| Systems Designer | Phase 1 | Open |
