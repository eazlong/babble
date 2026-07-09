# Godot启动验证清单（Phase 1 CCGS合并后）

## 启动前检查

### 1. 文件完整性检查（已通过✅）

**核心文件（7个）**：
- ✅ save_system.gd（已修改）
- ✅ scene_management_system.gd（已修改）
- ✅ scene_config.gd
- ✅ scene_config_loader.gd（已修改支持自定义路径）
- ✅ scene_loader.gd
- ✅ scene_transition.gd
- ✅ scene_state_machine.gd

**UI文件（1个）**：
- ✅ ui_framework.gd

**配置文件（3个）**：
- ✅ spirit_forest.json（格式正确）
- ✅ spell_library.json
- ✅ rainbow_garden.json

**修改文件（3个）**：
- ✅ project.godot（autoload配置正确）
- ✅ GameManager.gd（调用SaveSystem）
- ✅ MainMenuController.gd（初始化SceneManagementSystem）

---

## Godot编辑器启动验证

### Step 1: 打开项目
```bash
# 方法A：通过Godot编辑器GUI
打开Godot编辑器 → Import Project → 选择：
/Users/gongzuoyonghu/Documents/code/games/lauguage_game/apps/godot-client/project.godot

# 方法B：通过命令行（如果有godot命令）
cd /Users/gongzuoyonghu/Documents/code/games/lauguage_game/apps/godot-client
godot4 --editor
```

### Step 2: 检查Autoload加载

**预期结果**：
- 编辑器底部输出日志应显示：
  ```
  UIFramework: Creating CanvasLayers...
  SaveSystem: Initialized
  GameManager: Loaded progress
  SceneManagementSystem: Initialized
  ```

**如果出现错误**：
- ❌ "UIFramework not found" → 检查project.godot路径是否正确
- ❌ "SceneConfigLoader: Failed to open directory" → 检查JSON文件路径

---

### Step 3: 运行MainMenu场景（F5）

**预期行为**：
1. ✅ UIFramework自动创建4层CanvasLayer：
   - Layer 0 (layer=0): SceneCanvasLayer
   - Layer 1 (layer=10): HUDCanvasLayer
   - Layer 2 (layer=20): DialogueCanvasLayer
   - Layer 3 (layer=30): OverlayCanvasLayer

2. ✅ MainMenuController._ready()输出：
   ```
   [MainMenu] _ready() called
   [MainMenu] SceneManagementSystem initialized with 3 configs
   ```

3. ✅ SceneManagementSystem._ready()输出：
   ```
   SceneManagementSystem: Initialized and ready
   system_initialized signal emitted
   ```

4. ✅ CoachOverlay正常显示精灵动画

**如果出现错误**：
- ❌ CanvasLayer未创建 → 检查UIFramework._ready()
- ❌ SceneManagementSystem未初始化 → 检查JSON路径
- ❌ 场景配置加载失败 → 检查SceneConfigLoader.load_scene_configs()

---

### Step 4: 测试SaveSystem功能

**手动测试保存**：
```gdscript
# 在GameManager._ready()添加调试输出：
func _ready() -> void:
    load_progress()
    print("GameManager: Testing SaveSystem...")
    save_progress()
    SaveSystem.save_completed.connect(func(slot_id): print("Save completed to slot %d" % slot_id))
```

**预期结果**：
- ✅ 控制台输出：
  ```
  GameManager: Testing SaveSystem...
  Save completed to slot 1
  ```
- ✅ 文件创建：`user://saves/save_slot_1.json`
- ✅ JSON格式正确（包含player_name、lxp_score等字段）

**如果出现错误**：
- ❌ "Invalid slot ID" → SaveSystem.save()调用错误
- ❌ "Save operation already in progress" → 并发保存冲突
- ❌ JSON文件未创建 → 检查user://目录权限

---

### Step 5: 测试LoadSystem功能

**手动测试加载**：
```gdscript
# 在GameManager添加：
func test_load() -> void:
    SaveSystem.load(1)
    SaveSystem.load_completed.connect(func(slot_id, data):
        print("Load completed: player_name=%s, lxp_score=%d" % [data.player_name, data.lxp_score])
    )
```

**预期结果**：
- ✅ 控制台输出：
  ```
  Load completed: player_name=张三, lxp_score=100
  ```
- ✅ GameManager状态正确恢复

---

### Step 6: 测试场景切换

**测试场景配置**：
```gdscript
# 在MainMenuController添加：
func test_scene_transition() -> void:
    print("SceneManagementSystem unlocked scenes: ", SceneManagementSystem._unlocked_scenes)
    print("Attempting to enter spirit_forest...")
    SceneManagementSystem.enter_scene("spirit_forest")
```

**预期结果**：
- ✅ 输出：
  ```
  SceneManagementSystem unlocked scenes: ["spirit_forest"]
  Attempting to enter spirit_forest...
  scene_entering signal: spirit_forest
  Transition started: fade_in
  Transition completed
  scene_entered signal: spirit_forest
  ```

---

## 调试输出建议

### 在关键节点添加print：

**UIFramework._ready()**：
```gdscript
func _ready() -> void:
    _setup_cjk_font()
    _create_canvas_layers()
    print("UIFramework: Created 4 CanvasLayers (Scene=0, HUD=10, Dialogue=20, Overlay=30)")
```

**SceneManagementSystem.initialize()**：
```gdscript
func initialize(scene_configs: Array) -> bool:
    print("SceneManagementSystem.initialize: Loading %d configs" % scene_configs.size())
    # ... existing code ...
    print("SceneManagementSystem: First scene unlocked: %s" % first_id)
```

**SaveSystem.save()**：
```gdscript
func save(slot_id: int, custom_data: Dictionary) -> void:
    print("SaveSystem.save: Saving to slot %d, data keys: %s" % [slot_id, custom_data.keys()])
```

---

## 常见错误排查

### 错误1：Autoload加载顺序错误
**症状**：`SaveSystem not found`或`SceneManagementSystem not found`
**解决**：检查project.godot [autoload]部分顺序

### 错误2：JSON路径错误
**症状**：`SceneConfigLoader: Failed to open directory`
**解决**：检查MainMenuController中的路径参数是否为`"res://assets/resources/scene_configs/"`

### 错误3：CanvasLayer创建失败
**症状**：UI节点找不到父CanvasLayer
**解决**：检查UIFramework是否正确添加到SceneTree.root

### 错误4：SaveSystem异步保存阻塞
**症状**：游戏卡顿或保存无响应
**解决**：检查Thread是否正常启动，_process是否启用

---

## 验证成功标志

✅ **全部通过标准**：
1. Godot编辑器打开无错误
2. MainMenu场景运行无崩溃
3. 控制台输出：
   - UIFramework创建CanvasLayers
   - SceneManagementSystem初始化成功
   - SaveSystem保存/加载成功
4. 场景切换流畅（淡入淡出动画正常）
5. JSON文件正确生成（user://saves/save_slot_1.json）

---

**验证完成后请报告结果**：
- 通过哪些检查
- 遇到哪些错误
- 控制台输出的关键日志