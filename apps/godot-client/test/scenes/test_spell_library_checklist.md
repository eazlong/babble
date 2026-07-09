# SpellLibrary场景手动测试清单

## 测试环境准备

**启动步骤**：
1. 从SpiritForest完成徽章解锁
2. 点击"前往图书馆"按钮
3. 进入SpellLibrary场景

---

## 测试清单

### 1. 场景初始化验证

**测试步骤**：
- [ ] 场景加载无错误
- [ ] Luna NPC显示
- [ ] Teacher NPC显示
- [ ] CoachOverlay显示在Layer 3
- [ ] Bookshelf显示（书籍未排序）
- [ ] BadgeUI隐藏
- [ ] NavigationUI隐藏

**预期Console输出**：
```
[SpellLibrary] Quest status: {...}
[SpellLibrary] Dialogue started with: luna
```

---

### 2. Luna介绍流程

**测试步骤**：
1. 等待Luna介绍对话
2. DialogueBox显示"你好！我是 Luna..."
3. TTS播放完成
4. MicPanel显示
5. 开始整理书籍任务

**验证点**：
- [ ] DialogueBox显示在Layer 2
- [ ] CoachOverlay显示Luna提示
- [ ] TTS音频清晰
- [ ] VoicePipeline启动

---

### 3. 整理书籍任务

**测试步骤**：
1. DialogueBox显示"图书馆的魔法书都乱了..."
2. 依次说出："Big Book"、"Small Book"、"Red"

**验证点**：
- [ ] 每个分类激活对应书籍（视觉变化）
- [ ] 语音识别准确
- [ ] 3次完成后自动进入课堂指令任务

**Console输出**：
```
[SpellLibrary] Organized book category: big (1/3)
[SpellLibrary] Organized book category: small (2/3)
[SpellLibrary] Organized book category: red (3/3)
```

---

### 4. 课堂指令任务

**测试步骤**：
1. Teacher NPC出现
2. DialogueBox显示"我是 Teacher！..."
3. 依次说出："Stand Up"、"Open The Book"、"Read Aloud"

**验证点**：
- [ ] Teacher NPC对话切换
- [ ] 每个指令正确识别
- [ ] 错误指令显示hint
- [ ] 3次完成后进入对话练习

---

### 5. 对话练习任务

**测试步骤**：
1. Luna重新对话
2. DialogueBox显示"让我们和 Luna 聊聊天..."
3. 回答3个问题：
   - "你最喜欢图书馆里的什么书？"
   - "你最喜欢的颜色是什么？"
   - "如果让你写一本魔法书，你会写什么？"

**验证点**：
- [ ] 每个问题正确显示
- [ ] 语音回答自由输入
- [ ] 3轮完成后庆祝动画

---

### 6. 徽章解锁流程

**测试步骤**：
1. BadgeUI显示（Library Badge图标）
2. GameManager.lxp_score增加100
3. NavigationUI显示（前往彩虹花园按钮）

**验证点**：
- [ ] BadgeUI动画流畅
- [ ] GameManager.unlocked_areas包含"RainbowGarden"
- [ ] SaveSystem.save调用

---

### 7. UI分层验证

**测试步骤**：
1. 同时显示DialogueBox和CoachOverlay
2. 触达NPC和书籍元素

**验证点**：
- [ ] Layer 0（游戏世界）可交互
- [ ] Layer 2（DialogueBox）不阻挡交互
- [ ] Layer 3（CoachOverlay）最顶层

---

## 测试通过标准

SpellLibrary场景验证通过条件：
- ✅ 场景初始化正确
- ✅ Luna介绍流程完整
- ✅ 整理书籍任务完成（3/3）
- ✅ 课堂指令任务完成（3/3）
- ✅ 对话练习任务完成（3轮）
- ✅ 徽章解锁动画流畅
- ✅ UI分层正确
- ✅ 场景过渡正常

---

**测试执行人**：________
**测试日期**：________
**测试结果**：✅ PASS / ❌ FAIL