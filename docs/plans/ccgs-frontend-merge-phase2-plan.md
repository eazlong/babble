# Phase 2 CCGS前端合并计划

## Phase 1回顾（已完成✅）

**已完成工作**：
- ✅ 基础设施层：UI框架、场景管理、保存系统
- ✅ 12个GDScript + 3个JSON文件迁移
- ✅ project.godot autoload配置
- ✅ GameManager/MainMenuController集成
- ✅ Godot编辑器验证通过

---

## Phase 2范围：交互增强层

### 目标系统

**音频捕获系统**（audio_capture_system.gd + 相关）：
- 环状缓冲（128KB防溢出）
- 静音检测（RMS阈值 + 超时）
- 自动增益控制（目标-18dBFS）
- 低通滤波（5kHz）+ DC阻塞（60Hz）
- 噪声门限（150 RMS）
- 跨平台权限管理（Android适配）

**对话UI系统**（dialogue_ui.gd + bubble_component.gd）：
- 状态机（HIDDEN → IDLE → DISPLAYING → WAITING）
- 对话队列管理（最多50条）
- BubbleComponent动态创建
- Layer 2 CanvasLayer管理
- Tween生命周期管理

**HUD系统**（hud_controller.gd + elements/overlays/panels）：
- HUD控制器
- HUD元素（进度条等）
- HUD覆盖层
- HUD面板

**UI迁移**：
- CoachOverlay迁移到Layer 3（OverlayCanvasLayer）
- DialogueBox迁移到Layer 2（DialogueCanvasLayer）

---

## Phase 2迁移策略

### 问题1：音频捕获系统是否需要？

**LinguaQuest现状**：
- 已有VoicePipeline.gd（简化版）
  - 静音检测（0.015阈值 + 2.5s超时）
  - 最小语音时长（0.5s）
  - Record总线 + AudioEffectCapture
  - **无滤波器、无自动增益、无环状缓冲**

**CCGS音频捕获优势**：
- ✅ 更高质量的音频（滤波+增益）
- ✅ 防溢出机制（环状缓冲）
- ✅ 性能预算管理（单帧5ms）
- ❌ 增加复杂度（23KB代码）

**推荐决策**：
- **方案A**：保持VoicePipeline（简化版），不迁移audio_capture_system
  - 优势：LinguaQuest桌面端为主，不需要跨平台权限管理
  - 劣势：音频质量较低，可能有噪音
  
- **方案B**：迁移audio_capture_system，替代VoicePipeline
  - 优势：音频质量提升，架构统一
  - 劣势：需要修改VoicePipeline调用方（HybridAPI、DialogueManager）

---

### 问题2：对话UI系统是否需要？

**LinguaQuest现状**：
- DialogueManager.gd（WebSocket驱动）
- DialogueBox.gd（autoload单例，静态接口）
- **无状态机、无队列管理**

**CCGS对话UI优势**：
- ✅ 状态机驱动（避免对话混乱）
- ✅ 队列管理（防止对话重叠）
- ✅ Layer 2管理（符合UI分层）

**推荐决策**：
- **方案A**：迁移dialogue_ui + bubble_component，替代DialogueBox
  - 优势：架构统一，防止对话重叠
  - 劣势：需要修改DialogueManager调用方式
  
- **方案B**：保持DialogueBox，暂不迁移
  - 优势：风险低，不影响现有代码
  - 劣势：架构不统一，可能出现对话混乱

---

### 问题3：HUD系统是否需要？

**LinguaQuest现状**：
- **无HUD系统**（RewardAnimation + AchievementPanel直接在场景树）

**CCGS HUD优势**：
- ✅ HUD控制器（统一管理）
- ✅ HUD元素（进度条、状态指示器）
- ✅ Layer 1管理（符合UI分层）

**推荐决策**：
- **方案B**：暂不迁移HUD系统
  - 原因：LinguaQuest教育游戏HUD需求简单（奖励展示为主）
  - 未来可按需迁移（如果需要实时进度指示器）

---

### 问题4：UI迁移优先级？

**CoachOverlay迁移到Layer 3**：
- 优势：符合UI分层，Overlay激活时自动dim下层
- 劣势：需要修改SpiritForestController、SpellLibraryController、RainbowGardenController引用
- 影响：3个场景控制器（每个16KB代码）

**DialogueBox迁移到Layer 2**：
- 优势：符合UI分层，对话与游戏世界分离
- 劣势：需要修改DialogueManager调用方式
- 影响：DialogueManager.gd（6KB代码）

---

## 我的推荐Phase 2优先级

### 优先级排序

**P0（高优先级）**：
1. ✅ CoachOverlay迁移到Layer 3（符合UI分层，风险可控）
2. ✅ DialogueBox迁移到Layer 2（符合UI分层，风险可控）

**P1（中优先级）**：
3. ⚠️ 对话UI系统（可选：如果出现对话混乱问题）

**P2（低优先级）**：
4. ❌ 音频捕获系统（可选：如果音频质量有问题）
5. ❌ HUD系统（暂不需要）

---

## Phase 2实施计划（P0部分）

### 文件范围（预估）

**迁移文件**：
- 无需迁移新文件（使用Phase 1已有的UIFramework）

**修改文件**（3个）：
- CoachOverlay.gd（修改父节点为OverlayCanvasLayer）
- DialogueBox.gd（修改父节点为DialogueCanvasLayer）
- DialogueManager.gd（修改调用DialogueBox的方式）

**修改场景文件**（3个.tscn）：
- SpiritForest.tscn（CoachOverlay节点结构）
- SpellLibrary.tscn
- RainbowGarden.tscn

---

## Phase 2关键决策点

请回答以下问题以确定Phase 2范围：

### 问题1：音频捕获系统
**是否需要迁移audio_capture_system替代VoicePipeline？**
- A. 保持VoicePipeline（简化版）— 推荐
- B. 迁移audio_capture_system（高质量版）

### 问题2：对话UI系统
**是否需要迁移dialogue_ui + bubble_component？**
- A. 暂不迁移，保持DialogueBox — 推荐（风险低）
- B. 迁移dialogue_ui系统（队列+状态机）

### 问题3：UI迁移范围
**CoachOverlay和DialogueBox迁移优先级？**
- A. 先迁移CoachOverlay（Layer 3），后迁移DialogueBox（Layer 2）— 推荐
- B. 同时迁移两者
- C. 只迁移CoachOverlay

### 问题4：场景控制器修改
**是否愿意修改3个场景控制器（SpiritForestController等）？**
- A. 是，修改以适配UI分层 — 推荐
- B. 否，暂不迁移UI

---

**请回答以上4个问题，我将根据答案制定详细的Phase 2实施计划。**