# BeginningFP 美术资源清单（序章：蜃影初醒）

**版本**: 5.0（主人房开场 + 魔法投影版）
**日期**: 2026-09-14
**所属场景**: BeginningFP（序章第一人称）
**依赖文档/场景**: `assets/scenes/BeginningFP.tscn`, `assets/scripts/scenes/BeginningFPController.gd`, `assets/scenes/components/FeifeiBody.tscn`, `assets/scripts/components/FeifeiBody.gd`, `assets/resources/shaders/effects/wake_eye_open.gdshader`
**正典依据**: `apps/godot-client/docs/new/Story.md` 序章、`apps/godot-client/docs/new/PRD-v1.md` §8、`apps/godot-client/docs/adr/0001-prologue-owner-room-canon.md`

---

## 正典前提（v5.0）

- 序章不再发生在客栈外迷雾荒地，也不再有“看见客栈 / 走进客栈”演出。
- 玩家在蜃影客栈主人房的床上醒来；第一人称 POV，床不进画面。
- 腓腓救回玩家时客栈已主动认主：大门/主人房自行打开、阵法第一点光回应。腓腓说出事实，原因保留为长线悬念。
- 世界观揭示改为腓腓在床前的魔法投影（复用 `beginning_mist_continents.png`），不是天窗或窗外实景。
- 主人房基准背景与 MirageInnIntroduction 共用，保证醒来与导览是同一个空间。

---

## 总体风格指南

### 艺术风格定位

| 要素 | 规范 | 说明 |
|------|------|------|
| 整体风格 | 卡通 + 东方幻想 + 温暖主人房 | 儿童友好，不是恐怖开局，也不是纯装饰卧室 |
| 叙事氛围 | 从安稳睡眠中醒来，逐渐意识到客栈已认主 | 低对比晨光/暖光起手，投影出现后加入魔法金与青灰 |
| 色彩饱和度 | 中等饱和度（50-70%） | 比大厅更私密、更安静；重点留给魔法投影 |
| 线条特征 | 圆润木结构、柔和布幔、无尖锐棱角 | 与 MirageInnIntroduction 主人房规格一致 |
| 光影处理 | 暖木色 + 窗边晨光；睡醒前可用低亮度遮罩 | 睁眼遮罩边缘柔和，不用惊吓式暗场 |
| 魔法元素 | 投影青灰 + 神器微光金 | 六道光与投影雾是唯一强魔法焦点 |

### 色彩系统

| 色彩类型 | 色彩值 | 用途 |
|----------|--------|------|
| 客栈木棕 | `#4A3324` | 主人房木结构、柜体、床架 |
| 暖灯金 | `#F2D17A` | 晨光、枕边暖光、Feifei 提示重点 |
| 神器微光金 | `#F5D25A` | 投影中的六道光、第一点光回应 |
| 投影青灰 | `#B3C7C7` | 混沌迷雾投影、远方大陆雾带 |
| 深梦黑 | `#000000` | 睁眼前遮罩、眼睑 shader 底色 |
| UI 深蓝 | `#1A1A26` | 星星条、任务追踪器背景 |

### 第一人称视角规格

| 要素 | 规范 | 说明 |
|------|------|------|
| 基准分辨率 | 1920x1080 (16:9) | `BeginningFP.tscn` 主目标分辨率 |
| 玩家角色 | 不可见 | 序章不展示玩家身体；床保持在镜头下方/身后 |
| 醒来机位 | 主人房 POV（从床上看向房间） | 背景中不要出现完整床铺；被角/枕头虚焦边缘可选 |
| Feifei 位置 | 复用 `FeifeiBody` 床边/近景位 | 具体锚点以 `FeifeiBody.gd` 为准 |
| HUD 安全区 | 中心 80% 保留可读 | Feifei、气泡、投影不得遮挡任务追踪与麦克风 |
| 移动方式 | 镜头/剧情驱动 | 本场景不是自由探索房间 |

---

## 1. 场景装配要求

### 1.1 场景定位

| 要素 | 规格 | 说明 |
|------|------|------|
| 视觉主题 | 蜃影客栈主人房 · 晨间醒来 | 安稳、温暖、带一点旧木头的岁月感 |
| 剧情焦点 | 睁眼醒来、认主事实、命名、魔法投影 | 不做独立可点选物清单 |
| NPC 范围 | 仅 Feifei | 不包含客栈其他 NPC |
| 环境范围 | 主人房内景 + 剧情投影 | 不出现客栈外荒地/森林/雾天地面 |
| 交互重点 | 语音唤醒、命名、接受主线 | 交互由 Controller 和对话流驱动 |

### 1.2 场景分层规格

| 层 | 节点/资源 | 规格 | 说明 |
|----|-----------|------|------|
| 主人房背景 | `OwnerRoomBackground` / `mirage_inn_owner_room_bg.png` | 2560x1600 源图按 0.75/0.675 放到 1920x1080；或直接导出 1920x1080 | 由 `assets/sprites/feifei/room_1.png` 迁移命名；屋内应有柜体/窗/窗帘/桌面等可读陈设，无床 |
| 魔法投影层 | `MistCoveredContinents` / `beginning_mist_continents.png` | 1320x220；位置约 `(960,350)`，显隐与呼吸由 Controller 控制 | 表现为腓腓在床前投出的幻象，不是天空；可加柔光边 |
| 投影光效 | `beginning_projection_glow.png`（可选） | 约 1400x520，PNG+Alpha | 投影背后柔光/粒子，不遮挡 Feifei 与 HUD |
| 睁眼遮罩 | `WakeEyes` / `wake_eye_open.gdshader` | 全屏 ColorRect + ShaderMaterial | 三段式：眼睑张开 → 停顿 → 世界淡入 |
| Feifei | `FeifeiLayer` / `FeifeiBody.tscn` | 复用现有肩膀/提示/说话状态 | 不再使用旧 `FeifeiShoulder` 路径 |
| HUD | `HUDLayer` | 星星条、任务追踪器、指南针 | 沿用现有 UI 资源 |
| Overlay | `OverlayLayer` | 徽章、睁眼遮罩 | 沿用现有层级 |
| 麦克风 | `MicLayer` | 语音按钮 | 沿用语序章交互规格 |

**退役资源（不再被 BeginningFP 引用）**:
- `assets/textures/backgrounds/fog.png`
- `assets/textures/backgrounds/beginning_trees_far.png`
- `assets/textures/backgrounds/beginning_trees_mid.png`
- `assets/textures/backgrounds/forest_ground.png`
- `assets/textures/objects/beginning_mirage_inn_ruins.png`
- `assets/textures/hotel/grass.png` / `level0.png` 等旧占位

### 1.3 Feifei 资产与动画要求

| 节点/资源 | 规格 | 美术要求 |
|-----------|------|----------|
| `FeifeiBody.tscn` | 复用现有组件；位置在床侧 | 0.3、0.4、1.0 缩放下表情可辨 |
| `default` / `fly` | 飞入与过场 | 兼容现有飞入动画 |
| `idle` | 床边待机 | 支持呼吸浮动 |
| `hint` | 提示/沉默重试 | 表情温和但明确 |
| `happy` | 玩家回答后庆祝 | 不产生过大位移 |
| 气泡 | `ui_feifei_bubble_fp.png` | 淡黄圆角、金色边框，指向 Feifei |

### 1.4 运行时 Overlay/Prop 资产

| 运行时节点 | 实现 | 正式资源要求 |
|------------|------|--------------|
| `WakeEyes` | 全屏 ColorRect + `wake_eye_open.gdshader` | 可继续用 shader；眼睑边缘柔和 |
| `MistCoveredContinents` | `mid_layer` 上的 Sprite2D | `beginning_mist_continents.png`，作为室内魔法投影 |
| `ProjectionGlow`（可选） | 投影片后的柔光 | `beginning_projection_glow.png` 或 shader |
| 尘光粒子（可选） | 主人房内漂浮微尘 | `inn_room_dust_motes.png`，低密度、不抢焦点 |
| `BadgeUI` | 序章完成徽章 | `badge_beginning.png` + `BadgeLabel` |

### 1.5 HUD/Overlay 替换项

| 节点 | 正式资源要求 |
|------|--------------|
| `HUDLayer/StarBar/Background` / `Fill` | `ui_starbar_bg.png` + `ui_starbar_fill.png`，顶部居中 |
| `HUDLayer/QuestTracker/Background` | `ui_quest_tracker_bg.png`；任务文案支持两行中文 |
| `HUDLayer/MicButton/Button` | `ui_mic_button_idle.png` / `ui_mic_button_recording.png`，默认隐藏 |
| `HUDLayer/MagicCompass` | `ui_compass_bg.png` + `ui_compass_arrow.png` |
| `OverlayLayer/BadgeUI/BadgeIcon` | `badge_beginning.png`；“序章完成”由 `BadgeLabel` 渲染 |

---

## 2. 资产清单

### 2.1 P0 必需资产

| 资源 | 路径建议 | 尺寸 | 用途 |
|------|----------|------|------|
| `mirage_inn_owner_room_bg.png` | `assets/textures/backgrounds/` | 1920x1080（或 2560x1600 等比） | 主人房基准背景，与 MirageInnIntroduction 共用 |
| `beginning_mist_continents.png` | `assets/textures/backgrounds/` | 1320x220 | 室内魔法投影：六块大陆与雾带 |
| `wake_eye_open.gdshader` | 现有 | shader | 睁眼遮罩 |
| `feifei_frames.tres` | `assets/sprites/feifei/` | SpriteFrames | Feifei `default/idle/hint/happy` |
| `ui_feifei_bubble_fp.png` | `assets/textures/ui/fp/` | 200x100 | Feifei 气泡 |
| `ui_starbar_bg.png` / `ui_starbar_fill.png` | `assets/textures/ui/fp/` | 400x40 / 380x30 | 星星条 |
| `ui_quest_tracker_bg.png` | `assets/textures/ui/fp/` | 250x120 | 任务面板 |
| `ui_mic_button_idle.png` / `ui_mic_button_recording.png` | `assets/textures/ui/fp/` | 80x80 | 语音按钮 |
| `ui_compass_bg.png` / `ui_compass_arrow.png` | `assets/textures/ui/fp/` | 100x100 / 60x60 | 指南针 |
| `badge_beginning.png` | `assets/textures/ui/` | 150x150 | 序章完成徽章 |

### 2.2 P1 重要资产

| 资源 | 路径建议 | 尺寸 | 用途 |
|------|----------|------|------|
| `beginning_projection_glow.png` | `assets/textures/effects/` | 1400x520 | 投影背后柔光 |
| `inn_room_dust_motes.png` | `assets/textures/particles/` | 512x512 | 主人房内低密度尘光 |
| `badge_glow.png` | `assets/textures/ui/` | 180x180 | 徽章发光 |
| `badge_unlock_effect_01.png` ~ `_04.png` | `assets/textures/ui/` | 300x300 | 徽章解锁动画 |
| `ui_chaos_mist_overlay.png`（可选退役） | `assets/textures/ui/fp/` | 1920x1080 | 如保留可做投影氛围层，不再作为全屏迷雾 |

### 2.3 P2 增强资产

| 资源 | 路径建议 | 尺寸 | 用途 |
|------|----------|------|------|
| `beginning_continent_mist_veil.png` | `assets/textures/backgrounds/` | 1320x190 | 投影雾幕分层，可选 |
| `mirage_inn_owner_room_parallax_back.png` | `assets/textures/backgrounds/` | 1920x1080 | 主人房远景/窗外晨光分层，可选 |
| `feifei_glow.png` | `assets/sprites/feifei/` | 140x140 | Feifei 常驻光晕 |

---

## 3. UI 资产规格

沿用现有规格，不因序章开场变化而修改：

- `ui_starbar_bg.png`：400x40，深蓝半透明圆角条 + 金色细边框。
- `ui_starbar_fill.png`：380x30，橙金到魔法金渐变，获得星星时从左到右填充。
- `ui_quest_tracker_bg.png`：250x120，深蓝半透明面板 + 浅蓝边框，支持中文两行任务文案。
- `ui_feifei_bubble_fp.png`：200x100，淡黄圆角气泡，右下尾巴指向 Feifei。
- `ui_compass_bg.png` / `ui_compass_arrow.png`：100x100 / 60x60，古旧魔法罗盘 + 红金箭头，箭头可旋转且不裁边。
- `badge_beginning.png`：150x150，序章完成徽章；建议结合主人房木色、Feifei 光点或六道光；“序章完成”由 `BadgeLabel` 渲染，不画进图里。

---

## 4. 音频资源

| 资源 | 格式 | 时长 | 用途 |
|------|------|------|------|
| `beginning_ambient.ogg` | OGG Vorbis, 128kbps | 60-120s 循环 | 主人房晨间底噪：木屋轻响、远处院落声、低音量魔法泛音 |
| `magic_sparkle.ogg` | OGG Vorbis, 128kbps | 1-3s | Feifei 出现、投影点亮、提示反馈 |
| `badge_unlock.ogg` | OGG Vorbis, 128kbps | 5-8s | 序章完成徽章解锁 |
| `wind_soft.ogg` | 退役 | - | 原雾地风声不再用于序章 |

---

## 5. 资源目录结构

```text
assets/
├── sprites/
│   └── feifei/
│       ├── feifei_fly_01.png ...
│       ├── feifei_glow.png
│       └── feifei_frames.tres
├── textures/
│   ├── backgrounds/
│   │   ├── mirage_inn_owner_room_bg.png   # 与 MirageInnIntroduction 共用
│   │   ├── beginning_mist_continents.png  # 室内魔法投影
│   │   └── beginning_continent_mist_veil.png
│   ├── effects/
│   │   └── beginning_projection_glow.png
│   ├── particles/
│   │   └── inn_room_dust_motes.png
│   └── ui/
│       ├── badge_beginning.png
│       ├── badge_glow.png
│       └── fp/
│           ├── ui_feifei_bubble_fp.png
│           ├── ui_starbar_bg.png
│           ├── ui_starbar_fill.png
│           ├── ui_quest_tracker_bg.png
│           ├── ui_mic_button_idle.png
│           ├── ui_mic_button_recording.png
│           ├── ui_compass_bg.png
│           └── ui_compass_arrow.png
└── audio/
    ├── beginning_ambient.ogg
    ├── magic_sparkle.ogg
    └── badge_unlock.ogg
```

---

## 6. 制作优先级

| 批次 | 内容 | 目标 |
|------|------|------|
| 第一批 | `mirage_inn_owner_room_bg.png`（迁移命名 `room_1.png`） | 主人房开场与世界成立 |
| 第二批 | Feifei 统一 `SpriteFrames`、`ui_feifei_bubble_fp.png` | 修复 Feifei 状态动画与提示气泡 |
| 第三批 | `beginning_mist_continents.png` 投影化、`beginning_projection_glow.png` | 六道光视觉锚点 |
| 第四批 | 星星条、任务面板、麦克风、指南针、徽章 | 移除 HUD/Overlay 占位 |
| 第五批 | 睁眼 shader、尘光粒子、音频 | 提升序章演出质量 |

---

## 7. 验收标准

### 7.1 技术验收

| 项目 | 标准 |
|------|------|
| 分辨率 | 主人房背景与全屏 UI 按 1920x1080 制作或等比缩放 |
| Alpha | Feifei、UI、投影、光效 Alpha 正确 |
| SpriteFrames | Feifei 包含 `default/idle/hint/happy` 动画名 |
| 层级 | Feifei 高于 HUD、低于 Overlay；投影位于主人房背景之上 |
| 占位移除 | 不再引用 `assets/textures/hotel/grass.png` / `level0.png` |
| 退役检查 | `BeginningFP.tscn` 不再引用 fog / trees / ground / inn ruins |

### 7.2 风格验收

| 项目 | 标准 |
|------|------|
| 序章氛围 | 温暖、安稳的醒来；魔法投影带来世界观尺度，但不恐怖 |
| 儿童友好 | 形状圆润，避免尖锐、压迫或惊吓元素 |
| 同一空间 | 主人房与 MirageInnIntroduction 第一站看起来是同一个房间 |
| Feifei 可读性 | 0.3 缩放下仍能识别表情和身体轮廓 |
| UI 可读性 | 中文文本不溢出、不被装饰遮挡 |
| 视觉焦点 | 醒来→Feifei→投影→六道光→徽章，按剧情阶段清晰转移 |

### 7.3 性能验收

| 项目 | 标准 |
|------|------|
| 纹理尺寸 | 单张背景不超过 2560x1600；角色帧保持 307x307 或按实际需要裁切 |
| Draw Calls | UI/投影尽量复用材质，避免大量独立小图层 |
| 动画帧数 | Feifei 核心状态帧数可控；投影呼吸为 shader/tween 而非逐帧 |
| Overdraw | 睁眼遮罩、投影雾 Alpha 克制，避免多层全屏高 Alpha 叠加 |

---

## 相关文档

- `apps/godot-client/assets/scenes/BeginningFP.tscn`
- `apps/godot-client/assets/scripts/scenes/BeginningFPController.gd`
- `apps/godot-client/assets/scenes/components/FeifeiBody.tscn`
- `apps/godot-client/design/art/mirage_inn_introduction_art_assets.md`
- `apps/godot-client/docs/adr/0001-prologue-owner-room-canon.md`
