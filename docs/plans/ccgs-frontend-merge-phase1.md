# Phase 1 CCGS前端合并计划

## 已确认的10个关键决策

### 1. Phase 1范围
- ✅ 基础设施层：UI框架、场景管理、保存系统

### 2. 目录结构
- ✅ 保持CCGS结构，创建：
  - `assets/scripts/core/`
  - `assets/scripts/ui/framework/`
  - `assets/resources/scene_configs/`

### 3. 文件范围（共15个文件）
- ✅ **核心文件（10个）**：
  - `scene_management_system.gd`
  - `scene_state_machine.gd`
  - `scene_loader.gd`
  - `scene_transition.gd`
  - `save_system.gd`
  - `scene_config.gd`
  - `scene_config_loader.gd`
  - `ui_framework.gd`
  - `signal_registry.gd` ❌（已决定不迁移）
  - 实际：8个核心文件

- ✅ **可选文件（2个）**：
  - `scene_config.gd`
  - `scene_config_loader.gd`
  - 已确认方案B，改为必须迁移

- ✅ **JSON配置文件（3个）**：
  - `spirit_forest.json`
  - `spell_library.json`
  - `rainbow_garden.json`

### 4. GameManager冲突处理
- ✅ 方案A：保留GameManager + SaveSystem作为组件
- SaveSystem不替代GameManager，而是被GameManager调用

### 5. SaveSystem适配修改
- ✅ 方案A：通用化，接受任意字典
- 删除所有依赖注入（CharacterDataSystem、SpiritCollectionManager、SceneManagementSystem、InputManager）
- 修改`save(slot_id: int)` → `save(slot_id: int, custom_data: Dictionary)`
- GameManager调用：`SaveSystem.save(1, GameManager._get_save_data())`

### 6. SceneManagementSystem适配修改
- ✅ 方案A：最小化依赖，纯生命周期管理
- 删除所有依赖注入（InputManager、CharacterDataSystem、NarrativeDialogueSystem、SaveSystem）
- 保留核心功能：状态机、场景配置注册、解锁验证、过渡动画、信号机制
- 删除功能：Block/Unblock input、Register primary NPC、Load dialogue tree

### 7. UI框架集成策略
- ✅ 方案A：渐进式，保持现状
- Phase 1不强制迁移现有UI（CoachOverlay、DialogueBox保持原样）
- 新增UI使用UI框架（Layer 1-3）

### 8. SignalRegistry决策
- ✅ 方案A：不迁移SignalRegistry
- UIFramework、SceneManagementSystem、SaveSystem自带信号已足够

### 9. Autoload注册方式
- ✅ 方案A：全部注册为autoload
- 修改`project.godot`添加3个autoload：
  - `UIFramework` → Layer 0（最先加载）
  - `SaveSystem` → Layer 1
  - `SceneManagementSystem` → Layer 2（GameManager之后）
- Autoload顺序：UIFramework → SaveSystem → GameManager → SceneManagementSystem → 其他7个

### 10. 场景配置文件内容
- ✅ 方案B：完整迁移SceneConfig/Loader + JSON配置
- 创建`assets/resources/scene_configs/`目录
- 创建3个JSON文件定义场景配置

---

## 文件迁移清单（12个GDScript + 3个JSON = 15个文件）

### 从CCGS迁移的文件

#### 核心系统（8个文件）
```
CCGS路径                                         LinguaQuest路径
src/core/scene_management_system.gd       → assets/scripts/core/scene_management_system.gd
src/core/scene_state_machine.gd           → assets/scripts/core/scene_state_machine.gd
src/core/scene_loader.gd                  → assets/scripts/core/scene_loader.gd
src/core/scene_transition.gd              → assets/scripts/core/scene_transition.gd
src/core/save_system.gd                   → assets/scripts/core/save_system.gd
src/core/scene_config.gd                  → assets/scripts/core/scene_config.gd
src/core/scene_config_loader.gd           → assets/scripts/core/scene_config_loader.gd
src/ui/framework/ui_framework.gd          → assets/scripts/ui/framework/ui_framework.gd
```

#### JSON配置文件（3个文件）
```
新建文件路径
assets/resources/scene_configs/spirit_forest.json
assets/resources/scene_configs/spell_library.json
assets/resources/scene_configs/rainbow_garden.json
```

---

## 需要修改的现有文件

### 1. `project.godot`（添加3个autoload）
```ini
[autoload]

UIFramework="*res://assets/scripts/ui/framework/ui_framework.gd"
SaveSystem="*res://assets/scripts/core/save_system.gd"
GameManager="*res://assets/scripts/autoload/GameManager.gd"
SceneManagementSystem="*res://assets/scripts/core/scene_management_system.gd"
HybridAPI="*res://assets/scripts/autoload/HybridAPI.gd"
VoicePipeline="*res://assets/scripts/autoload/VoicePipeline.gd"
DialogueManager="*res://assets/scripts/autoload/DialogueManager.gd"
AudioManager="*res://assets/scripts/autoload/AudioManager.gd"
DialogueBox="*res://assets/scripts/autoload/DialogueBox.gd"
CoachClient="*res://assets/scripts/autoload/CoachClient.gd"
QuestWebSocket="*res://assets/scripts/autoload/QuestWebSocket.gd"
```

### 2. `GameManager.gd`（修改保存逻辑）
- 删除：`save_progress()`、`load_progress()`内部实现
- 新增：调用SaveSystem的接口
```gdscript
func save_progress() -> void:
    var save_data = {
        "player_name": player_name,
        "player_age": player_age,
        "current_lang": current_lang,
        "unlocked_areas": unlocked_areas,
        "lxp_score": lxp_score,
        "completed_dialogues": completed_dialogues,
        "vocabulary_learned": vocabulary_learned
    }
    SaveSystem.save(1, save_data)

func load_progress() -> bool:
    var result = await SaveSystem.load(1)
    if result.success:
        var data = result.data
        player_name = data.get("player_name", "")
        player_age = data.get("player_age", 0)
        current_lang = data.get("current_lang", "zh")
        # ... 其他字段
        return true
    return false
```

### 3. `MainMenuController.gd`（初始化场景系统）
```gdscript
func _ready() -> void:
    # 加载场景配置
    var config_loader = SceneConfigLoader.new()
    var success = config_loader.load_configs("res://assets/resources/scene_configs/")
    if success:
        var configs = config_loader.get_all_scene_configs()
        SceneManagementSystem.initialize(configs.values())
```

---

## 实施步骤（Phase 1）

### Step 1：创建目录结构
```bash
mkdir -p assets/scripts/core
mkdir -p assets/scripts/ui/framework
mkdir -p assets/resources/scene_configs
```

### Step 2：迁移核心文件（12个GDScript）
- 复制8个核心文件到新目录
- 修改文件内的import路径（如果有）

### Step 3：修改迁移文件的依赖
- **SaveSystem.gd**：
  - 删除第66-147行（所有依赖注入变量和getter）
  - 删除第350-392行（_collect_save_data()）
  - 修改第399行`save(slot_id: int)` → `save(slot_id: int, custom_data: Dictionary)`
  - 修改第419-425行：使用传入的custom_data而不是调用_collect_save_data()

- **SceneManagementSystem.gd**：
  - 删除第36-39行（依赖注入变量声明）
  - 删除第137-146行（set_dependencies()方法）
  - 删除第205-206、232-233行（Block/Unblock input调用）
  - 删除第211-219行（Register NPC、Load dialogue tree）
  - 删除第287-288行（clear_active_npc调用）

### Step 4：创建JSON配置文件（3个）
- 创建spirit_forest.json、spell_library.json、rainbow_garden.json
- 定义场景ID、display_name、chapter、order、background_resource

### Step 5：修改现有文件
- 修改project.godot添加autoload
- 修改GameManager.gd调用SaveSystem
- 修改MainMenuController.gd初始化SceneManagementSystem

### Step 6：测试验证
- 启动Godot，验证autoload加载顺序
- 测试UIFramework创建4层CanvasLayer
- 测试SceneManagementSystem初始化
- 测试SaveSystem保存/加载（通过GameManager）

---

## 风险与注意事项

### 高风险修改
1. **SaveSystem多线程逻辑**（异步保存）：
   - CCGS使用Thread + _process轮询
   - LinguaQuest可能需要简化（await替代Thread）

2. **SceneManagementSystem状态机**：
   - CCGS有复杂的14步enter_scene流程
   - LinguaQuest简化后可能只需要5-6步

### 测试重点
- ✅ UIFramework CanvasLayer创建顺序
- ✅ SaveSystem异步保存不阻塞主线程
- ✅ SceneManagementSystem场景切换信号发射
- ✅ GameManager数据正确传递给SaveSystem

---

## 后续Phase 2规划（不在本次范围）

- 音频捕获系统（环状缓冲+增益+滤波）
- 对话UI系统（状态机+队列管理）
- HUD系统（进度条、元素、面板）
- 迁移CoachOverlay到Layer 3
- 迁移DialogueBox到Layer 2

---

**预计时间**：Phase 1实施约需2-3小时（包括测试验证）

---

## 实施完成状态（2026-06-22）

✅ **所有9个任务已完成**：
1. ✅ 创建目录结构（3个新目录）
2. ✅ 迁移SaveSystem核心文件（已删除依赖注入，修改save/load接口）
3. ✅ 迁移SceneManagementSystem核心文件（已删除依赖注入，保留核心生命周期）
4. ✅ 迁移SceneConfig系统文件（scene_config.gd + scene_config_loader.gd）
5. ✅ 迁移UIFramework文件
6. ✅ 创建场景配置JSON文件（spirit_forest.json、spell_library.json、rainbow_garden.json）
7. ✅ 修改project.godot添加autoload（UIFramework、SaveSystem、SceneManagementSystem）
8. ✅ 修改GameManager.gd调用SaveSystem
9. ✅ 修改MainMenuController.gd初始化场景系统

---

## 迁移文件总结

### 已迁移文件（12个GDScript + 3个JSON = 15个文件）

**核心系统（7个GDScript）**：
- save_system.gd（已修改：删除依赖注入、save接受custom_data、load返回data）
- scene_management_system.gd（已修改：删除依赖注入、保留生命周期管理）
- scene_state_machine.gd
- scene_loader.gd
- scene_transition.gd
- scene_config.gd
- scene_config_loader.gd

**UI系统（1个GDScript）**：
- ui_framework.gd

**配置文件（3个JSON）**：
- spirit_forest.json
- spell_library.json
- rainbow_garden.json

### 已修改文件（3个）

**project.godot**：
- 添加3个autoload（UIFramework、SaveSystem、SceneManagementSystem）
- Autoload顺序：UIFramework → SaveSystem → GameManager → SceneManagementSystem → 其他7个

**GameManager.gd**：
- save_progress()：调用SaveSystem.save(1, custom_data)
- load_progress()：保留同步加载逻辑（await异步集成待Phase 2）

**MainMenuController.gd**：
- _ready()：加载场景配置并初始化SceneManagementSystem

---

## 下一步建议

### 立即验证（高优先级）
1. **启动Godot编辑器**，验证autoload加载顺序
2. **运行MainMenu场景**，检查：
   - UIFramework是否创建4层CanvasLayer
   - SceneManagementSystem是否成功初始化
   - 场景配置JSON是否正确加载
3. **测试保存/加载**，通过GameManager验证SaveSystem

### 集成测试（Phase 2准备）
1. 等待SaveSystem.load_completed信号（异步）
2. SceneManagementSystem场景切换信号集成
3. UIFramework Layer管理（CoachOverlay迁移到Layer 3）

---

**实施时间**：约1.5小时（实际）