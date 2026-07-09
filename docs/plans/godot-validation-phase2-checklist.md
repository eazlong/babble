# Phase 2验证清单

## 修改内容总结

### DialogueBox迁移到Layer 2
- ✅ DialogueBox.gd改为extends Control（不再是CanvasLayer）
- ✅ _ready()添加到UIFramework的DialogueCanvasLayer
- ✅ 保持autoload单例（project.godot不变）

### CoachOverlay迁移到Layer 3
- ✅ CoachOverlay.gd _ready()从场景树移除，添加到OverlayCanvasLayer
- ✅ show_hint/show_hint_for_duration调用UIFramework.activate_overlay()
- ✅ hide_hint调用UIFramework.deactivate_overlay()
- ✅ 场景控制器无需修改（@onready引用仍有效）

---

## Godot编辑器验证步骤

### 1. 启动项目验证

打开Godot编辑器：
```
1. 打开Godot 4.6编辑器
2. 导入项目: apps/godot-client
3. 点击运行按钮（F5）
```

**预期结果**：
- ✅ 项目启动无错误
- ✅ Console输出：
  ```
  [UIFramework] Created 4 CanvasLayers (Scene=0, HUD=10, Dialogue=20, Overlay=30)
  [DialogueBox] Added to DialogueCanvasLayer (Layer 2)
  [CoachOverlay] Moved from scene tree to OverlayCanvasLayer (Layer 3)
  ```

---

### 2. DialogueBox验证

**测试步骤**：
1. 启动游戏，进入精灵森林场景
2. 观察Spark自我介绍时的DialogueBox显示

**预期结果**：
- ✅ DialogueBox显示在Layer 2（layer=20）
- ✅ DialogueBox不影响游戏世界（Layer 0）交互
- ✅ DialogueBox和CoachOverlay同时显示时，CoachOverlay在上层（Layer 3）

**调试验证**：
```
打开远程场景树调试器：
- 检查DialogueCanvasLayer (layer=20)节点下有DialogueBox子节点
```

---

### 3. CoachOverlay验证

**测试步骤**：
1. 进入精灵森林场景
2. 观察CoachOverlay初始显示（Spark自我介绍时）
3. 点击按钮触发coach提示（如果有）

**预期结果**：
- ✅ CoachOverlay显示在Layer 3（layer=30）
- ✅ CoachOverlay激活时，HUD和Dialogue层dim到30%不透明度
- ✅ CoachOverlay隐藏时，HUD和Dialogue恢复100%不透明度

**调试验证**：
```
打开远程场景树调试器：
- 检查OverlayCanvasLayer (layer=30)节点下有CoachOverlay子节点
- 检查OverlayCanvasLayer初始visible=false
- 检查CoachOverlay.show_hint调用后OverlayCanvasLayer.visible=true
```

---

### 4. UI分层验证

**测试步骤**：
1. 同时触发DialogueBox和CoachOverlay显示
2. 检查视觉层级关系

**预期结果**：
- ✅ Layer 0（游戏世界）在最底层
- ✅ Layer 1（HUD）在游戏世界之上
- ✅ Layer 2（DialogueBox）在HUD之上
- ✅ Layer 3（CoachOverlay）在最顶层
- ✅ CoachOverlay激活时，Layer 1-2 dim到30%

---

### 5. 场景控制器验证

**测试步骤**：
1. 测试3个场景：SpiritForest、SpellLibrary、RainbowGarden
2. 观察CoachOverlay在每个场景的表现

**预期结果**：
- ✅ SpiritForestController: coach_overlay引用有效
- ✅ SpellLibraryController: coach_overlay引用有效
- ✅ RainbowGardenController: coach_overlay引用有效
- ✅ CoachOverlay在每个场景都能正确迁移到Layer 3

---

## 可能的问题与解决方案

### 问题1：DialogueBox未显示在Layer 2

**症状**：DialogueBox不显示，或显示在错误位置

**诊断**：
```
检查Console输出是否有警告：
[DialogueBox] UIFramework DialogueCanvasLayer not found, adding to root
```

**原因**：UIFramework未初始化，或DialogueCanvasLayer创建失败

**解决方案**：
1. 检查project.godot autoload顺序：UIFramework必须在DialogueBox之前
2. 检查UIFramework._ready()是否创建了DialogueCanvasLayer

---

### 问题2：CoachOverlay未迁移到Layer 3

**症状**：CoachOverlay停留在场景树，未添加到OverlayCanvasLayer

**诊断**：
```
检查Console输出是否有警告：
[CoachOverlay] UIFramework OverlayCanvasLayer not found, staying in scene tree
```

**原因**：UIFramework未初始化，或OverlayCanvasLayer创建失败

**解决方案**：
1. 检查project.godot autoload顺序：UIFramework必须在SceneManagementSystem之前
2. 检查UIFramework._ready()是否创建了OverlayCanvasLayer

---

### 问题3：CoachOverlay引用失效

**症状**：场景控制器调用coach_overlay.show_hint()时报错

**诊断**：
```
检查场景控制器_ready()时序：
- @onready在节点_enter_tree时执行
- CoachOverlay._ready()在节点_enter_tree后执行
```

**原因**：@onready引用建立时，CoachOverlay仍未迁移，引用有效

**解决方案**：无需修改（理论正确）

---

### 问题4：Overlay未dim下层

**症状**：CoachOverlay显示时，HUD和Dialogue层不透明度未变化

**诊断**：
```
检查UIFramework.activate_overlay()是否被调用：
- CoachOverlay.show_hint()应调用UIFramework.activate_overlay()
```

**原因**：UIFramework.activate_overlay()未执行，或set_layer_opacity()失败

**解决方案**：
1. 检查CoachOverlay.show_hint()是否调用UIFramework.activate_overlay()
2. 检查UIFramework._hud_content和_dialogue_content节点是否存在

---

## 验证通过标准

Phase 2验证通过条件：
- ✅ 项目启动无错误
- ✅ DialogueBox显示在Layer 2（layer=20）
- ✅ CoachOverlay显示在Layer 3（layer=30）
- ✅ UI分层正确（0 → 10 → 20 → 30）
- ✅ Overlay激活时Layer 1-2 dim到30%
- ✅ 3个场景控制器coach_overlay引用有效

---

**请运行Godot编辑器，按以上步骤验证，并报告结果。**