# GUT测试执行指引

## 安装验证

**确认GUT已安装**：
```
打开Godot编辑器 → Project Settings → Plugins
检查是否有GUT插件（bitwes/Gut）
```

---

## 测试执行方式

### 方式1：编辑器运行

**步骤**：
1. 打开Godot编辑器
2. 菜单栏 → GUT → Run All Tests
3. 观察测试结果面板

**快捷键**：
- Ctrl+Shift+T（Windows/Linux）
- Cmd+Shift+T（Mac）

---

### 方式2：命令行运行

**步骤**：
```bash
cd apps/godot-client

# 运行所有测试
godot --headless --script addons/gut/gut_cmdln.gd

# 运行单个测试文件
godot --headless --script addons/gut/gut_cmdln.gd -gtest=test/core/test_save_system.gd

# 运行特定测试方法
godot --headless --script addons/gut/gut_cmdln.gd -gtest=test/core/test_save_system.gd -gmethod=test_save_validates_slot_id
```

---

### 方式3：配置文件运行

**步骤**：
```bash
# 使用gutconfig.json配置
godot --headless --script addons/gut/gut_cmdln.gd -gconfig=gutconfig.json
```

---

## 测试文件清单

### 单元测试（GUT）

| 文件 | 覆盖系统 | 测试数量 |
|------|---------|---------|
| test/core/test_save_system.gd | SaveSystem | 25个测试 |
| test/ui/test_ui_framework.gd | UIFramework | 20个测试 |
| test/autoload/test_dialogue_manager.gd | DialogueManager | 15个测试 |

**估算覆盖率**：
- SaveSystem: 85%
- UIFramework: 80%
- DialogueManager: 75%

---

### 手动测试清单

| 文件 | 场景 | 测试步骤 |
|------|------|---------|
| test/scenes/test_spirit_forest_checklist.md | SpiritForest | 8个流程验证 |
| test/scenes/test_spell_library_checklist.md | SpellLibrary | 7个流程验证 |
| test/scenes/test_rainbow_garden_checklist.md | RainbowGarden | 8个流程验证 |

---

## 测试结果验证

### 单元测试验证

**成功标准**：
- ✅ 所有测试断言通过（绿色）
- ❌ 无测试失败（红色）
- ❌ 无测试错误（橙色）

**Console输出示例**：
```
[GUT] Running 60 tests...
[GUT] test_save_system.gd: All tests passed (25/25)
[GUT] test_ui_framework.gd: All tests passed (20/20)
[GUT] test_dialogue_manager.gd: 1 test failed (14/15)
[GUT] Total: 59 passed, 1 failed
```

---

### 手动测试验证

**成功标准**：
- ✅ 所有流程步骤完成
- ✅ Console输出正确（无错误）
- ✅ UI分层正确（Layer 0 → 10 → 20 → 30）
- ✅ DialogueBox和CoachOverlay正确迁移
- ✅ 语音识别准确（颜色、数字、天气等）

---

## 测试覆盖报告

### 执行测试

**生成覆盖率报告**：
```bash
# 运行测试并生成报告
godot --headless --script addons/gut/gut_cmdln.gd -gconfig=gutconfig.json -gcoverage=true
```

**查看报告**：
```
打开Godot编辑器 → GUT → View Coverage Report
```

---

## 测试失败处理

### 问题诊断步骤

1. **检查Console输出**：
   ```
   查找红色ERROR或橙色WARNING
   ```

2. **检查测试断言**：
   ```
   打开测试面板 → 点击失败测试 → 查看断言详情
   ```

3. **检查依赖状态**：
   ```
   确认autoload顺序正确（UIFramework → SaveSystem → GameManager）
   ```

---

### 常见失败原因

**原因1：UIFramework未初始化**
```
错误：[DialogueBox] UIFramework DialogueCanvasLayer not found
解决：检查project.godot autoload顺序
```

**原因2：SaveSystem测试目录权限**
```
错误：Failed to create test_saves directory
解决：检查user://目录权限（Mac/Linux）
```

**原因3：VoicePipeline未启动**
```
错误：VoicePipeline.is_listening = false
解决：检查音频权限（Mac需要麦克风权限）
```

---

## 测试执行时间估算

| 测试类型 | 估算时间 | 备注 |
|---------|---------|------|
| SaveSystem单元测试 | 2-3分钟 | 25个测试，异步等待 |
| UIFramework单元测试 | 1-2分钟 | 20个测试，动画等待 |
| DialogueManager集成测试 | 3-5分钟 | 依赖TTS/VoicePipeline |
| SpiritForest手动测试 | 10-15分钟 | 完整流程验证 |
| SpellLibrary手动测试 | 10-12分钟 | 完整流程验证 |
| RainbowGarden手动测试 | 12-15分钟 | 完整流程验证 |

**总计**：约40-50分钟

---

## 测试执行优先级

**推荐执行顺序**：
1. P0：SaveSystem单元测试（最关键）
2. P0：UIFramework单元测试（UI分层验证）
3. P1：DialogueManager集成测试
4. P1：SpiritForest手动测试（第一个场景）
5. P1：SpellLibrary手动测试
6. P1：RainbowGarden手动测试

---

## CI/CD集成（可选）

**GitHub Actions配置**：
```yaml
name: Godot Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run GUT Tests
        run: |
          cd apps/godot-client
          godot --headless --script addons/gut/gut_cmdln.gd -gconfig=gutconfig.json
```

---

**测试执行人**：________
**测试日期**：________
**测试结果**：✅ PASS / ❌ FAIL
**覆盖率**：________%