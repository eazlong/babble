# 测试覆盖补充计划

## 当前测试现状

### 后端服务测试（已有覆盖）
- ✅ 7个服务有单元测试（17个.test.ts文件）
  - auth-service
  - content-filter-service
  - content-service
  - dialogue-service
  - quest-service
  - reward-service
  - spirit-coach-service
- ✅ Vitest测试框架（apps/game-client/vitest.config.ts）

### E2E测试（部分覆盖）
- ✅ 6个Playwright测试文件（tests/e2e/）
  - chapter1-flow.test.ts
  - child-mode.test.ts
  - quest-flow.test.ts
  - reward-drop.test.ts
  - voice-pipeline.test.ts
- ⚠️ **测试目标**：parent-dashboard（家长控制台Web应用）
- ❌ **缺口**：不覆盖Godot桌面客户端

### Godot客户端测试（零覆盖）
- ❌ **29个GDScript文件**，完全没有单元测试
- ❌ **关键文件**：
  - SaveSystem.gd（保存系统）
  - SceneManagementSystem.gd（场景管理）
  - UIFramework.gd（UI框架）
  - DialogueBox.gd（对话框）
  - CoachOverlay.gd（教练覆盖层）
  - GameManager.gd（游戏管理）
  - DialogueManager.gd（对话管理）
  - VoicePipeline.gd（语音管线）
  - 3个场景控制器（SpiritForest、SpellLibrary、RainbowGarden）

---

## 测试策略

### 问题：Godot桌面客户端无法使用Playwright E2E测试

**原因**：
- Playwright针对Web应用（需要HTTP服务器）
- Godot客户端是桌面应用（导出为.exe/.app）
- 家长控制台（parent-dashboard）是Web应用，可以使用Playwright

**解决方案**：
- **方案A**：使用GUT（Godot Unit Test）框架补充GDScript单元测试 — 推荐
  - 优势：原生GDScript测试，无需导出Web版本
  - 劣势：学习曲线，需要安装GUT插件

- **方案B**：创建详细手动测试清单（类似Phase 1-2验证）
  - 优势：无需额外框架，快速执行
  - 劣势：非自动化，难以持续集成

- **方案C**：导出Godot为Web版本，使用Playwright测试
  - 优势：自动化E2E测试
  - 劣势：需要导出Web版本（不符合桌面客户端定位）

---

## 推荐决策：方案A + 方案B

**混合策略**：
1. **单元测试**：GUT框架测试核心系统（SaveSystem、UIFramework等）
2. **集成测试**：手动测试清单测试场景流程（3个场景控制器）
3. **E2E测试**：Playwright测试家长控制台（已有覆盖）

---

## Phase 3测试补充计划

### Step 1：GUT框架安装

**安装步骤**：
```bash
# 1. 下载GUT插件
cd apps/godot-client
# Godot Asset Library搜索"GUT"，或从GitHub下载：
# https://github.com/bitwes/Gut

# 2. 解压到addons/gut目录
mkdir -p addons/gut
# 解压GUT插件文件

# 3. 启用插件
# project.godot添加：
# [addons]
# gut/addon_directory="addons/gut"
```

**验证**：
- 打开Godot编辑器 → Project Settings → Plugins → 启用GUT

---

### Step 2：SaveSystem单元测试

**测试文件**：`test/core/test_save_system.gd`

**测试场景**：
1. **初始化测试**：
   - 测试保存目录创建
   - 测试初始状态（IDLE）

2. **保存测试**：
   - 测试slot_id验证（1-3有效，其他拒绝）
   - 测试checksum计算
   - 测试异步保存线程
   - 测试save_completed信号

3. **加载测试**：
   - 测试slot_id验证
   - 测试文件不存在处理
   - 测试checksum验证
   - 测试version验证
   - 测试默认值填充
   - 测试load_completed信号

4. **删除测试**：
   - 测试slot_id验证
   - 测试文件不存在（idempotent）
   - 测试save_deleted信号

5. **并发测试**：
   - 测试并发保存拒绝
   - 测试并发加载拒绝

**估算工作量**：50-80行测试代码，3-4小时

---

### Step 3：UIFramework单元测试

**测试文件**：`test/ui/test_ui_framework.gd`

**测试场景**：
1. **CanvasLayer创建测试**：
   - 测试4个CanvasLayer创建（Scene=0, HUD=10, Dialogue=20, Overlay=30）
   - 测试layer属性值

2. **页面栈测试**：
   - 测试push_page（最多3层）
   - 测试pop_page（空栈安全处理）
   - 测试动画防抖

3. **Overlay激活测试**：
   - 测试activate_overlay（Layer 1-2 dim到30%）
   - 测试deactivate_overlay（恢复100%）
   - 测试信号发射

**估算工作量**：40-60行测试代码，2-3小时

---

### Step 4：DialogueManager集成测试

**测试文件**：`test/autoload/test_dialogue_manager.gd`

**测试场景**：
1. **对话启动测试**：
   - 测试start_npc_dialogue（npc_id、greeting）
   - 测试dialogue_started信号
   - 测试DialogueBox.show_message调用

2. **对话结束测试**：
   - 测试end_dialogue
   - 测试dialogue_ended信号
   - 测试VoicePipeline.stop_listening
   - 测试GameManager.completed_dialogues更新

3. **静音检测测试**：
   - 测试_reset_silence_watch（15秒超时）
   - 测试_on_silence_timeout触发

**估算工作量**：30-50行测试代码，2-3小时

---

### Step 5：场景控制器手动测试清单

**测试文档**：
- `test/scenes/test_spirit_forest_checklist.md`
- `test/scenes/test_spell_library_checklist.md`
- `test/scenes/test_rainbow_garden_checklist.md`

**测试步骤**（参考Phase 1-2验证清单）：
1. 场景初始化验证
2. NPC对话流程验证
3. 语音输入验证
4. 任务完成验证
5. 徽章解锁验证
6. UI分层验证（CoachOverlay Layer 3）

**估算工作量**：3个文档，2-3小时

---

## 测试覆盖率目标

### 单元测试覆盖率估算

| 文件 | 估算覆盖率 | 备注 |
|------|-----------|------|
| SaveSystem.gd | 85% | 核心保存系统，高优先级 |
| UIFramework.gd | 80% | UI框架，高优先级 |
| SceneManagementSystem.gd | 70% | 场景管理，中优先级 |
| DialogueManager.gd | 75% | 对话管理，中优先级 |
| GameManager.gd | 60% | 游戏状态，低优先级（简单）|
| VoicePipeline.gd | 60% | 语音管线，低优先级 |
| DialogueBox.gd | 70% | 对话框，中优先级 |
| CoachOverlay.gd | 70% | 教练覆盖层，中优先级 |

**总体覆盖率目标**：70-75%（考虑GDScript测试难度）

---

## 执行优先级

### P0（高优先级）
1. ✅ GUT框架安装
2. ✅ SaveSystem单元测试（最关键系统）
3. ✅ UIFramework单元测试（UI分层验证）

### P1（中优先级）
4. ⚠️ DialogueManager集成测试
5. ⚠️ 场景控制器手动测试清单

### P2（低优先级）
6. ❌ GameManager单元测试
7. ❌ VoicePipeline单元测试
8. ❌ DialogueBox单元测试

---

## 关键决策点

### 问题1：测试策略选择
**如何测试Godot桌面客户端？**
- A. GUT单元测试 + 手动测试清单 — 推荐
- B. 仅手动测试清单（无自动化）
- C. 导出Web版本 + Playwright E2E测试

### 问题2：执行优先级
**是否按P0→P1→P2顺序执行？**
- A. 是，先安装GUT，然后SaveSystem/UIFramework测试 — 推荐
- B. 否，仅手动测试清单（快速验证）
- C. 否，补充后端服务测试（优先非前端）

---

**请回答以上2个问题，我将根据答案开始测试补充工作。**