# RainbowGarden场景手动测试清单

## 测试环境准备

**启动步骤**：
1. 从SpellLibrary完成徽章解锁
2. 点击"前往彩虹花园"按钮
3. 进入RainbowGarden场景

---

## 测试清单

### 1. 场景初始化验证

**测试步骤**：
- [ ] 场景加载无错误
- [ ] Sunny NPC显示
- [ ] Flora NPC隐藏（等待种花任务）
- [ ] WeatherCrystal显示（4个损坏水晶）
- [ ] AnimalHidingSpot显示（3个隐藏点）
- [ ] FlowerGarden显示（未种植）
- [ ] CoachOverlay显示在Layer 3
- [ ] BadgeUI隐藏
- [ ] NavigationUI隐藏

---

### 2. Sunny介绍流程

**测试步骤**：
1. 等待Sunny介绍对话
2. DialogueBox显示"你好！我是 Sunny！..."
3. TTS播放完成
4. 开始修复天气水晶任务

---

### 3. 修复天气水晶任务

**测试步骤**：
1. DialogueBox显示"说出天气单词来修复水晶..."
2. 依次说出："Sunny"、"Rainy"、"Cloudy"（完成3个即可）

**验证点**：
- [ ] 每个天气词汇激活对应水晶
- [ ] 语音识别准确（英文天气词汇）
- [ ] 3个完成后自动进入找动物任务

**Console输出**：
```
[RainbowGarden] Fixed weather crystal: sunny (1/4)
[RainbowGarden] Fixed weather crystal: rainy (2/4)
[RainbowGarden] Fixed weather crystal: cloudy (3/4)
```

---

### 4. 找迷路小动物任务

**测试步骤**：
1. DialogueBox显示"小动物们迷路了..."
2. 依次说出：
   - "Cat in the tree"
   - "Dog under the bridge"
   - "Bird in the bush"

**验证点**：
- [ ] 每个动物+位置组合识别准确
- [ ] 动物出现动画（从隐藏点）
- [ ] 3只完成后进入种花任务

---

### 5. 种植魔法花朵任务

**测试步骤**：
1. Flora NPC出现
2. DialogueBox显示"让我教你种魔法花..."
3. 依次说出："Plant Red"、"Water Blue"、"Grow Yellow"

**验证点**：
- [ ] Flora NPC正确显示
- [ ] 每个动词+颜色组合识别准确
- [ ] 花朵种植动画
- [ ] 3朵完成后庆祝动画

---

### 6. 徽章解锁流程

**测试步骤**：
1. BadgeUI显示（Rainbow Garden Badge图标）
2. GameManager.lxp_score增加150
3. NavigationUI显示（返回主菜单按钮）

**验证点**：
- [ ] BadgeUI动画流畅
- [ ] GameManager.lxp_score正确增加
- [ ] SaveSystem.save调用
- [ ] 主菜单按钮显示

---

### 7. UI分层验证

**测试步骤**：
1. 同时显示DialogueBox和CoachOverlay
2. 触达NPC、水晶、动物、花朵

**验证点**：
- [ ] Layer 0（游戏世界）可交互
- [ ] Layer 2（DialogueBox）不阻挡交互
- [ ] Layer 3（CoachOverlay）最顶层

---

### 8. 返回主菜单验证

**测试步骤**：
1. 点击"返回主菜单"按钮
2. 观察场景过渡
3. 进入MainMenu场景

**验证点**：
- [ ] 场景过渡流畅
- [ ] MainMenu显示已完成状态
- [ ] GameManager状态正确保存

---

## 测试通过标准

RainbowGarden场景验证通过条件：
- ✅ 场景初始化正确
- ✅ Sunny介绍流程完整
- ✅ 修复天气水晶任务完成（3/4）
- ✅ 找迷路小动物任务完成（3/3）
- ✅ 种植魔法花朵任务完成（3/3）
- ✅ 徽章解锁动画流畅
- ✅ UI分层正确
- ✅ 返回主菜单正常

---

**测试执行人**：________
**测试日期**：________
**测试结果**：✅ PASS / ❌ FAIL