# 第一人称视角改造 — 技术审查报告

**审查日期**: 2026-07-01
**审查对象**: `first-person-spirit-forest-spec.md` 规格文档
**审查范围**: Godot 4.6 技术可行性 + 现有代码兼容性

---

## 1. 规格技术可行性判定

| 规格要点 | 判定 | 说明 |
|---------|------|------|
| 6层分层结构（ParallaxBackground） | ✅ 可行 | 现有场景已用5层ParallaxLayer，直接复用 |
| 90°水平FOV | ⚠️ 简化 | Godot 2D无真实FOV概念，改为"标准16:9画面" |
| 节点式移动 + 淡入淡出 | ✅ 可行 | ColorRect + Tween实现，0.8秒过渡 |
| TreeSpirit眼神跟随 | ✅ 可行 | EyePupil子节点 + lerp跟随鼠标X轴 |
| Spark肩膀位置(0.9, 0.75) | ✅ 可行 | Control节点全屏锚定，动态计算位置 |
| 凝视系统（2秒注视触发） | ⚠️ MVP延后 | 需要RayCast2D+Timer，MVP先省略 |
| 魔法指南针 | ✅ 可行 | Control节点 + 方向箭头，MVP简化为固定箭头 |
| Camera2D第一人称配置 | ⚠️ 不需要 | 第一人称2D实际不需要Camera2D移动，场景固定 |

## 2. 现有代码兼容性

### 2.1 完全兼容（无需修改）

| 系统 | 原因 |
|------|------|
| HybridAPI (autoload) | HTTP客户端，与视角无关 |
| VoicePipeline (autoload) | 麦克风控制，与视角无关 |
| DialogueManager (autoload) | 对话状态机，与视角无关 |
| AudioManager (autoload) | TTS播放，与视角无关 |
| GameManager (autoload) | 全局状态，与视角无关 |
| quest-service API | 纯后端，与客户端呈现无关 |
| spirit-coach-service | WebSocket协议不变 |
| reward-service | 事件监听不变 |
| assessment-service | ASR→LLM流程不变 |

### 2.2 不修改现有代码

| 组件 | 决策 | 原因 |
|------|------|------|
| CoachOverlay.gd | **不修改** | 创建独立的SparkShoulder.gd替代，避免破坏第三人称版 |
| SpiritForestController.gd | **不修改** | 创建独立的SpiritForestFPController.gd |
| SpiritForest.tscn | **不修改** | 创建独立的SpiritForestFP.tscn |

## 3. 实施文件清单

### 新增文件

| 文件路径 | 用途 | 行数 |
|---------|------|------|
| `assets/scripts/components/FirstPersonNavigator.gd` | 节点导航 + 淡入淡出 | ~100 |
| `assets/scripts/components/SparkShoulder.gd` | 肩膀精灵(简化CoachOverlay) | ~150 |
| `assets/scripts/scenes/SpiritForestFPController.gd` | 第一人称场景控制器 | ~300 |
| `assets/scenes/SpiritForestFP.tscn` | 第一人称场景文件 | - |

### 不修改任何现有文件

## 4. 风险评级

| 风险 | 等级 | 说明 | 缓解 |
|------|------|------|------|
| 场景资源缺失(TreeSpirit大尺寸贴图) | MEDIUM | 现有tree-big.png可能不够大 | 使用scale=1.5放大，后续替换美术 |
| SparkShoulder与CoachOverlay功能重叠 | LOW | 两者独立运行 | 第一人称场景只使用SparkShoulder |
| 导航信号连接时序 | LOW | navigator.transition_completed可能在ready前触发 | _ready中连接信号 |
| 眼神跟随性能 | LOW | _process中lerp每帧执行 | 仅TreeSpirit可见时执行 |

## 5. MVP简化决策

| 规格要求 | MVP决策 | 原因 |
|---------|---------|------|
| 5个节点 | ✅ 保留5个 | 实现成本低 |
| 凝视系统 | ❌ 延后 | 需要额外输入处理逻辑 |
| 空间音频 | ❌ 延后 | 需要AudioStreamPlayer配置 |
| NPC嘴型同步 | ❌ 延后 | 需要音素分析 |
| 魔法指南针旋转 | ⚠️ 简化为固定箭头 | MVP阶段方向指示即可 |

## 6. 测试验证方式

### 运行测试
```bash
# 在Godot编辑器中
# 1. 导入 apps/godot-client/ 项目
# 2. 打开 assets/scenes/SpiritForestFP.tscn
# 3. 点击运行场景 (F6)
```

### 验收检查项
- [ ] 场景加载后看到ParallaxBackground
- [ ] Spark肩膀位置(右下)显示，有呼吸动画
- [ ] 1秒后自动导航到节点B(TreeSpirit位置)
- [ ] TreeSpirit显示在画面中央
- [ ] 花朵/宝箱按任务进度显示
- [ ] HUD元素(星条/任务/麦克风/指南针)位置正确
- [ ] Badge解锁动画正常

## 7. 后续工作

1. **美术替换**: 将占位ColorRect替换为正式贴图
2. **凝视系统**: 添加RayCast2D + Timer实现注视触发
3. **Spark引导注视**: 添加身体朝向+手臂指向动画
4. **场景间导航**: MainMenu添加SpiritForestFP入口按钮
5. **SpellLibrary/RainbowGarden**: 同样改造为第一人称版
