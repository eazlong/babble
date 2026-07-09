# SpiritForest场景手动测试清单

## 测试环境准备

**启动步骤**：
1. 打开Godot编辑器
2. 运行项目（F5）
3. 进入精灵森林场景（从MainMenu选择）

---

## 测试清单

### 1. 场景初始化验证

**测试步骤**：
- [ ] 场景加载无错误
- [ ] Spark NPC显示
- [ ] CoachOverlay显示在右上角
- [ ] MicPanel初始隐藏
- [ ] MagicFlowers显示（3朵）
- [ ] TreasureChest显示（锁定状态）
- [ ] BadgeUI隐藏
- [ ] NavigationUI隐藏

**预期Console输出**：
```
[UIFramework] Created 4 CanvasLayers (Scene=0, HUD=10, Dialogue=20, Overlay=30)
[DialogueBox] Added to DialogueCanvasLayer (Layer 2)
[CoachOverlay] Moved from scene tree to OverlayCanvasLayer (Layer 3)
[SpiritForest] Quest status: {...}
```

---

### 2. Spark自我介绍流程

**测试步骤**：
1. 等待1秒自动触发Spark介绍
2. 观察DialogueBox显示"你好！我是 Spark..."
3. 观察CoachOverlay显示相同文本
4. 等待TTS播放完成（Spark语音）
5. 观察VoicePipeline启动（MicPanel显示）
6. 语音输入名字："Alice"

**验证点**：
- [ ] DialogueBox显示在Layer 2（与游戏世界分离）
- [ ] CoachOverlay显示在Layer 3（最顶层）
- [ ] CoachOverlay激活时，HUD和Dialogue层dim到30%
- [ ] TTS音频清晰播放
- [ ] MicPanel显示动画（脉冲效果）
- [ ] 语音识别成功（Console输出："Player name set to: Alice"）
- [ ] quest完成报告（Console输出："Quest report result: {...}"）

---

### 3. 颜色任务流程

**测试步骤**：
1. 等待颜色教程对话
2. DialogueBox显示"让我教你颜色魔法..."
3. TTS播放完成
4. MicPanel显示
5. 依次说出："Red"、"Blue"、"Yellow"

**验证点**：
- [ ] 每个颜色激活对应花朵（视觉变化）
- [ ] DialogueBox每次显示NPC响应
- [ ] CoachOverlay显示提示文本
- [ ] 语音识别准确（颜色词汇）
- [ ] 3次完成后自动进入Oakley遭遇

**Console输出**：
```
[SpiritForest] Activated color: red (1/3)
[SpiritForest] Activated color: blue (2/3)
[SpiritForest] Activated color: yellow (3/3)
[SpiritForest] Quest report result: {"badge_unlocked": null, "lxp_earned": 20}
```

---

### 4. Oakley遭遇流程

**测试步骤**：
1. 观察Oakley NPC出现
2. DialogueBox显示"你好，小魔法师！..."
3. TTS播放完成
4. 等待3秒进入数字任务

**验证点**：
- [ ] Oakley NPC正确显示（之前隐藏）
- [ ] DialogueBox切换到Oakley对话
- [ ] CoachOverlay显示Oakley提示
- [ ] TTS音频切换到Oakley语音

---

### 5. 数字任务流程

**测试步骤**：
1. DialogueBox显示"仔细数一数..."
2. MicPanel显示
3. 语音输入："Seven" 或 "7" 或 "七"
4. 观察宝箱解锁动画

**验证点**：
- [ ] DialogueBox显示Oakley提示
- [ ] 语音识别数字准确
- [ ] 宝箱解锁（视觉变化）
- [ ] 错误提示（如果输入错误数字）
- [ ] 3次错误后显示hint："提示：比5多，比10少..."

**Console输出**：
```
[SpiritForest] Found number: 7
[SpiritForest] Quest report result: {"badge_unlocked": "forest_badge"}
```

---

### 6. 徽章解锁流程

**测试步骤**：
1. 观察庆祝动画
2. BadgeUI显示（Forest Badge图标）
3. 等待3秒
4. NavigationUI显示（前往图书馆按钮）

**验证点**：
- [ ] BadgeUI动画流畅（fade-in + scale）
- [ ] GameManager.lxp_score增加100
- [ ] GameManager.unlocked_areas包含"SpellLibrary"
- [ ] GameManager.save_progress()调用（SaveSystem.save）
- [ ] NavigationUI显示"前往图书馆"按钮

**Console输出**：
```
[SaveSystem] Saving to slot 1, data keys: [...]
[SaveSystem] Initialized, save directory: user://saves/
[SpiritForest] Badge earned
```

---

### 7. UI分层验证

**测试步骤**：
1. 同时显示DialogueBox和CoachOverlay
2. 观察视觉层级关系
3. 触达游戏世界元素（NPC、花朵）

**验证点**：
- [ ] Layer 0（游戏世界）在最底层
- [ ] Layer 2（DialogueBox）在游戏世界之上
- [ ] Layer 3（CoachOverlay）在最顶层
- [ ] CoachOverlay激活时，游戏世界不dim（仅HUD和Dialogue dim）
- [ ] DialogueBox不阻挡游戏世界交互

---

### 8. 场景过渡验证

**测试步骤**：
1. 点击"前往图书馆"按钮
2. 观察场景过渡动画
3. 进入SpellLibrary场景

**验证点**：
- [ ] 场景过渡流畅（无卡顿）
- [ ] SpellLibrary场景加载
- [ ] DialogueManager.end_dialogue()调用
- [ ] CoachOverlay正确迁移到新场景Layer 3

---

## 错误场景测试

### E1. 语音识别失败

**测试步骤**：
- 故意发出模糊语音
- 观察DialogueBox显示错误提示

**预期行为**：
- [ ] DialogueBox显示"抱歉，我没听清楚..."
- [ ] VoicePipeline重新启动
- [ ] 无crash，无无限循环

---

### E2. 长时间静音

**测试步骤**：
- 启动语音监听后保持静默15秒

**预期行为**：
- [ ] 静音计时器触发
- [ ] Coach干预事件发布（silence_timeout）
- [ ] CoachOverlay可能显示提示

---

### E3. 并发语音输入

**测试步骤**：
- 在TTS播放时尝试语音输入

**预期行为**：
- [ ] VoicePipeline等待TTS完成
- [ ] 无音频冲突

---

## 测试通过标准

SpiritForest场景验证通过条件：
- ✅ 场景初始化正确
- ✅ Spark介绍流程完整
- ✅ 颜色任务完成（3/3）
- ✅ Oakley遭遇触发
- ✅ 数字任务完成（正确输入）
- ✅ 徽章解锁动画流畅
- ✅ UI分层正确（Layer 0 → 2 → 3）
- ✅ 场景过渡正常
- ✅ 错误场景优雅处理

---

**测试执行人**：________
**测试日期**：________
**测试结果**：✅ PASS / ❌ FAIL
**备注**：________