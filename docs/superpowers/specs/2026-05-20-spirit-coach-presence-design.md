# 精灵教练常驻表现设计

## 背景

精灵教练第一版已通过 WebSocket 接收后端干预事件，并能在 Godot 客户端显示提示气泡。当前 `CoachOverlay` 仍偏向一次性提示组件，需要升级为游戏内常驻伙伴的通用表现层。

## 目标

- 精灵教练作为屏幕角落常驻伙伴存在。
- 视觉气质为轻柔治愈，避免遮挡主要玩法。
- 第一版支持 7 个通用状态：`idle`、`enter`、`exit`、`speaking`、`hint`、`thinking`、`happy`。
- 优先在 Godot 客户端落地，基于现有 `CoachOverlay.gd` 轻量扩展。
- 使用混合动效策略：状态切换和过渡由代码驱动，角色细节优先使用素材帧；缺素材时用 tween 模拟。

## 非目标

- 不修改后端协议。
- 不新增全局单例或复杂控制器。
- 不做多角色编排。
- 不实现完整队列系统。
- 不为 CocosCreator 同步实现。

## 架构边界

第一版只扩展 `apps/godot-client/assets/scripts/components/CoachOverlay.gd`，必要时调整场景节点属性。`CoachOverlay` 从“直接播放动画和显示气泡”升级为“精灵教练表现层”：对外提供统一状态入口，内部管理状态优先级、气泡显示、tween 生命周期和素材动画回退。

保留现有方法以兼容调用点：

- `fly_in_from(start_pos, end_pos, duration, callback)`
- `show_hint(text, emotion)`
- `hide_hint()`
- `set_emotion(emotion)`
- `show_hint_for_duration(text, emotion, ttl_ms)`

新增主入口：

- `play_state(state: String, text: String = "", ttl_ms: int = 0)`
- `show_presence()`
- `hide_presence()`

旧方法逐步包装到新入口，不立即删除。

## 状态设计

### `idle`

默认常驻态。角色停留在右下角，持续慢速上下漂浮和轻微缩放呼吸，气泡隐藏。

### `enter`

从屏幕边缘或当前位置轻柔进入角落。先淡入，再落位，结束后自动进入 `idle`。

### `exit`

反向淡出并轻微缩小。结束后隐藏角色和气泡。

### `speaking`

显示文本气泡，角色保持轻微活跃的说话节奏。没有专用说话素材时，用更短周期的呼吸/漂浮模拟。

### `hint`

显示稳定的提示气泡，适合短句、任务提醒和学习指引。角色动作比 `speaking` 更克制。

### `thinking`

漂浮幅度变小，节奏更慢，可用轻微发光或停顿感表达“正在思考”。没有专用素材时回退到 `idle` 动画配合 tween。

### `happy`

短暂鼓励态。做轻微上浮、弹性缩放或亮度增强，结束后自动回到 `idle`。

## 优先级和过渡规则

优先级从高到低：

1. `exit`
2. `enter`
3. `speaking`
4. `hint`
5. `happy`
6. `thinking`
7. `idle`

规则：

- `enter` 和 `exit` 可以打断普通状态。
- `speaking` 和 `hint` 可以打断 `thinking` 和 `idle`。
- `happy` 是短暂插入态，播放完成后回到 `idle`。
- 连续收到状态请求时，第一版只处理最高优先级或最新一次，避免 tween 堆叠。
- 每次切状态前停止当前状态相关 tween，避免缩放、透明度、位置叠加失控。

## 数据流

1. `DialogueManager`、`CoachClient` 或测试入口调用 `CoachOverlay`。
2. `CoachOverlay.play_state()` 接收状态名、可选文本和 TTL。
3. `CoachOverlay` 根据优先级决定是否切换。
4. `CoachOverlay` 停止旧 tween，播放素材动画或 fallback 动画。
5. 如果状态包含文本，更新气泡并按 TTL 自动隐藏。
6. 状态结束后回到 `idle`，除非当前状态已经被更高优先级请求替换。

## 素材动画回退

当 `AnimatedSprite2D.sprite_frames` 中存在同名动画时播放同名动画。否则按以下规则回退：

- `enter`、`exit`、`idle`、`thinking`、`happy` → `idle`
- `speaking`、`hint` → `idle`
- 保留现有 `fly_in_from()` 的 `fly` 动画使用方式；如果缺少 `fly`，回退到 `idle`

## 气泡规则

- `idle`、`enter`、`exit`、`thinking` 默认不显示气泡。
- `speaking`、`hint` 显示气泡。
- `happy` 可以不显示气泡；如果传入文本，则短暂显示鼓励文字。
- 气泡出现使用淡入和轻微缩放，隐藏使用淡出。
- TTL 为 0 时不自动隐藏；TTL 大于 0 时到期隐藏气泡并回到 `idle`。

## 验收标准

- 精灵默认能在屏幕角落常驻，持续轻柔呼吸和漂浮。
- 出场、退场不会突兀闪现或遮挡主要 UI。
- 收到提示文本时，气泡出现、文本可读、TTL 后能自动消失。
- `speaking`、`thinking`、`happy` 有可感知差异，但动作都保持轻柔。
- 连续状态请求不会导致 tween 叠加失控或气泡卡住。
- 现有 `show_hint_for_duration()`、`show_hint()`、`fly_in_from()` 兼容可用。
- 缺少同名素材动画时不会触发 AnimatedSprite2D 播放错误。

## 测试方式

- 在 Godot 主菜单或测试场景手动触发 7 个状态，确认视觉过渡。
- 通过现有教练 WebSocket 事件触发 `hint` 或 `speaking`，确认真实流程仍能显示。
- 检查缺少动画名时能回退到 `idle`。
- 如可用，运行 Godot CLI 脚本检查或打开编辑器确认脚本无语法错误。
- 若本地无法运行 Godot 编辑器，必须在交付说明中明确未做视觉实机验证。
