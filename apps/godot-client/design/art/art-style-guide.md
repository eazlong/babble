# LinguaQuest RPG 全局美术风格指南

**版本**: 1.0
**日期**: 2026-07-28
**适用范围**: `apps/godot-client/` 全部场景、UI、特效、角色资产
**性质**: 全局总纲。各场景美术清单（`beginning_art_assets.md`、`mirage_inn_introduction_art_assets.md` 等）只可细化本指南，不可违背。
**依赖文档**: `design/gdd/game-concept.md`、各 per-scene 美术清单

---

## 0. 文档定位

本指南把分散在各场景清单与 GDD 中的视觉规范抽离成**可复用**的权威参考。新增场景或委托新资产时，先读本指南，再查 per-scene 清单核对物件细节。本指南不重复 per-scene 物件清单。

---

## 1. 风格总则

### 1.1 整体定位

**儿童友好东方奇幻 2D 手绘绘本风**。面向中国小学四年级学生（9-10 岁），世界观为「迷雾岛 + 六大神器 + 失语之雾」的东方奇幻。

| 维度 | 规范 |
|------|------|
| 渲染方式 | 2D 手绘绘本风，非写实、非像素艺术 |
| 视角 | 纯第一人称 2D，基准分辨率 1920×1080 (16:9) |
| 色彩饱和度 | 中等（50-70%）；序章可降至 45-60%，客栈可升至 55-75% |
| 线条 | 柔和圆润，无尖锐棱角；角色、UI、远景剪影统一绘本感 |
| 光影 | 柔和渐变阴影，无硬切高光；大面积遮罩边缘必须羽化 |
| 魔法高光 | 金色 `#FFD700` 为主，浅青灰雾气 `#B3C7C7` 为辅 |
| 情绪基调 | 安全、温暖、有探索期待；破损只表现为空缺与旧痕，不表现恐怖 |

### 1.2 核心美学关键词

`children-friendly` · `oriental fantasy` · `storybook` · `rounded shapes` · `soft golden magic light` · `clean composition` · `readable focal point` · `elegant and uncluttered`

### 1.3 反支柱（不做的风格）

| 反支柱 | 理由 |
|--------|------|
| 西式魔法学院 / Spark / 精灵森林符号 | 已被迷雾岛世界观取代（见 GDD §15 命名替换规范） |
| 恐怖废墟、鬼屋、阴森旅店、血迹、尖锐裂纹 | 违背儿童友好支柱与「无失败惩罚」 |
| 写实厚涂、高对比 HDR、影视级材质 | 偏离绘本风，增加儿童认知负担 |
| 像素艺术、低分辨率复古风 | 与 1920×1080 高清绘本定位冲突 |
| 过度饱和糖果色铺满全屏 | 重点光可鲜明，背景必须稳 |
| 在背景图里写死大量英文/中文/教程文字 | 破坏本地化与教学词迭代 |
| 把场景物件画成明显按钮 | 第一人称场景以注视 + 语音推进，非点击操作 |

---

## 2. 色彩系统

### 2.1 主色板

| 色彩 | HEX | 用途 | 建议使用比例 |
|------|-----|------|--------------|
| 迷雾青灰 | `#B3C7C7` | 失语之雾、远方雾幕、雾气粒子 | 15-25%（序章可达 35%） |
| 深梦黑 | `#000000` | 苏醒前暗场、眼睑遮罩、Overlay 转场 | ≤10%，仅过渡用 |
| 森林绿（深） | `#2D5016` | 远景树线、深林剪影 | 10-15% |
| 森林绿（中） | `#4A7C29` | 中景树影、草地过渡 | 8-12% |
| 森林绿（浅） | `#6B8E23` | 地面草地、近景植被 | 5-10% |
| 土地棕 | `#8B6F47` | 木结构、地面细节、客栈建材 | 10-15% |
| 魔法金 | `#FFD700` | 飞飞光晕、徽记、阵法、神器微光 | ≤8%（重点色，克制使用） |
| UI 深蓝 | `#1A1A26` | 星星条、任务追踪器、语音按钮背景 | UI 专属，不计入场景比例 |

**比例原则**：魔法金是稀缺重点色，单帧画面金色面积占比建议 ≤8%，避免廉价感。雾气青灰是统一基底色，所有区域都应保留少量雾气以维持世界一致感。

### 2.2 客栈补充色板（蜃影客栈 / 词灵书阁专用）

| 色彩 | HEX | 用途 |
|------|-----|------|
| 客栈木棕 | `#4A3324` | 大厅、房门、玩家房间木结构 |
| 暖灯金 | `#F2D17A` | 大厅灯光、房门边缘、飞飞提示重点 |
| 阵法紫灰 | `#2B2638` | 阵法房间背景 |
| 神器微光金 | `#F5D25A` | 神器线索、阵法核心、空神器座边缘 |
| 书阁青绿 | `#214449` | 词灵书阁背景 |
| 词灵薄荷光 | `#B8FBE7` | 词灵、书阁漂浮书页 |
| 客房旧绿 | `#3D3D2D` | 客房预告区域、远方旅人门影 |
| UI 深底 | `#141419` | 任务面板、语音按钮深底 |

### 2.3 六大神器主色映射（建议）

> 以下神器主色 GDD 未明确指定，基于 §5.3 区域语义合理推断，标注「建议」。per-scene 清单可覆盖。

| 神器 | 象征区域 | 建议主色 | HEX | 推断依据 |
|------|----------|----------|-----|----------|
| 回声螺 | 雾湾 / 海边 | 海雾青 | `#7FA8AE` | 海岸 + 雾气，承接迷雾青灰但偏蓝 |
| 记忆玉简 | 长安集市 | 玉石青 | `#9CB89C` | 玉简材质 + 集市木棕衬托 |
| 彩灯莲 | 花灯庭院 | 多彩暖光 | `#F2A65A` 主 + 红/蓝/紫辅 | 花灯本身多色，主色取暖橙统一基调 |
| 风向罗盘 | 仙舟渡口 | 古铜金 | `#C89B3C` | 罗盘金属 + 渡口暮色 |
| 句法机关锁 | 词灵书阁 | 书阁青绿 | `#214449` | 沿用书阁背景色，机关锁同源 |
| 星河镜 | 岛心观星台 | 深蓝紫 | `#3D2B5F` | 夜空 + 星河 + 神秘汇聚 |

**使用规则**：神器主色仅在该神器所在区域、徽记、解锁特效中以重点色形式出现；不替代主色板的世界基底色。

### 2.4 明暗模式说明

本项目**不切换全局明暗模式**，通过场景级基调控制明暗：

| 场景类型 | 明暗策略 |
|----------|----------|
| 序章 / 苏醒前 | 低明度、低对比、朦胧雾感（深梦黑 + 迷雾青灰主导） |
| 探索区域（雾湾/集市/庭院/渡口） | 中明度、中对比、暖光主导 |
| 神器房间 / 阵法房间 | 中低明度、冷色背景 + 金色重点光 |
| 词灵书阁 | 中明度、青绿色独立空间，区别于外景 |
| 观星台 / 时光回廊 | 低明度、深蓝紫 + 星辉高光 |
| 客栈大厅 / 玩家房间 | 中高明度、暖木色、安全基地感 |

---

## 3. 角色美术规范

### 3.1 通用规范

| 要素 | 规范 |
|------|------|
| 轮廓 | 柔和圆润，外轮廓线 2-3px，色阶与填充区分而非硬描边 |
| 描边 | 不使用纯黑硬描边；使用比填充深 20-30% 的同色系轮廓 |
| 比例 | 头身比偏 Q 版（1:2 至 1:3），增强儿童亲和力 |
| 透明背景 | 所有角色帧必须 PNG + Alpha，边缘预乘检查，无黑边 |
| 帧率 | 逐帧角色（NPC / 玩家手部）：idle/talk 8-10 FPS，happy/hint 10-12 FPS，fly 5-8 FPS。**腓腓例外**——骨骼动画无帧率概念，节奏由关键帧曲线控制（见 §3.2） |
| 表情可读性 | 在 0.3 缩放下仍能识别表情与身体轮廓（序章飞飞硬性要求） |
| 帧间稳定性 | 帧间轮廓抖动 < 2px，避免闪烁（骨骼角色对应要求为形变不抖动） |

### 3.2 飞飞（Feifei / 腓腓）

> ⚠️ **架构变更（2026-09-15）：腓腓已从逐帧 SpriteFrames 改为骨骼动画。**
> 旧的 `feifei_frames.tres`（`AnimatedSprite2D` + 逐帧 PNG）与 `FeifeiShoulder.gd` **已废弃**。
> 现行实现为 `assets/scenes/components/FeifeiBody.tscn` + `FeifeiBody.gd`：
> **Skeleton2D + Polygon2D 逐顶点蒙皮（Spine 风格）**，部件采样单张图集 `feifei_part.png`。
> 美术交付物因此从「成百上千张逐帧 PNG」变为「**一张分层部件图集 + 骨骼绑定**」。
> 详见 `../../docs/feifei-character-design-guide.md`。

| 要素 | 规格 |
|------|------|
| 资源路径 | `assets/sprites/feifei/` |
| 图集 | `feifei_part.png` — 单张 2048×2048 透明图集，含全部可动部件 |
| 实现 | `assets/scenes/components/FeifeiBody.tscn`（Skeleton2D + 14 个蒙皮 Polygon2D） |
| 部件清单 | head / body / wings×2 / legs×2 / eyes / mouth / hands×2 / feature / ears×2 / tail |
| 骨骼树 | `body`(根) → `feature1` → `feature2`（头链）；`hand_left/right 1-4`、`leg_left/right 1-4`、`wing_left/right 1-3` |
| 动画库 | `AnimationPlayer`：`RESET` / `fly` / `idle`（身体骨骼）；`FaceAnimationPlayer`：`talk_mouth`（口型） |
| 面部层 | 眨眼由 `BlinkController.gd` 用 Tween 驱动 `eyes:polygon`；口型由 `talk_mouth` 驱动 `mouth:polygon` |
| 游戏内缩放 | 实例 `scale ≈ 0.1`（设计画布很大）；骨骼根位置 `(-1352, 184)` |
| 缩放档 | 0.3 / 0.4 / 1.0 三档都需表情可辨 |
| 动画约定 | 骨骼 `idle` 自带 `body:position:y` 浮动，**不要**再叠加根节点呼吸 tween；`happy` 由脚本 tween 叠加跳跃 + 1.3× 缩放 |
| 语言特权 | 飞飞是唯一可说中文的角色（提示、解释、引导） |
| 光晕 | 可选 `feifei_glow.png`（140×140）常驻金色光晕 |

**为什么脸不走骨骼**（三层分离架构）：眨眼/嘴型是离散状态，骨骼的连续旋转表达不了；面部做成独立部件层后可按状态切换。三路驱动器互不相交，可真正并行：

```text
AnimationPlayer（身体）    → 骨骼 + 面部 position/rotation/scale
FaceAnimationPlayer（嘴）  → mouth:polygon（talk_mouth 循环）
BlinkController（眼，Tween）→ eyes:polygon
```

> ⚠️ Godot 4.6 的 `AnimationPlayer` 是**单播放状态**（无图层 API），`play()` 会顶掉正在播的动画。因此口型与眨眼**不得**复用身体 AnimationPlayer。新增动画时须遵守该约束。

### 3.3 第一人称玩家手部

| 要素 | 规格 |
|------|------|
| 资源路径 | `assets/sprites/player/` |
| 可见内容 | 仅手部 / 随身道具，不可见全身角色 |
| 动画帧 | `idle`（4 帧）、`talk`（3 帧）、`walk`（6 帧）、`player_hands_idle` |
| 帧率 | idle 8 FPS、talk 10 FPS、walk 10-12 FPS |
| 透明背景 | 必须，手部边缘无黑边 |
| 出现时机 | 仅在需要表达玩家动作（递交物品、抬手示意）时出现，不常驻 |

### 3.4 NPC（以 oakley 为基准）

| 要素 | 规格 |
|------|------|
| 资源路径 | `assets/sprites/{npc_name}/` |
| 命名 | `{npc}_{state}_{NN}.png`，如 `oakley_idle_01.png` |
| 必需状态 | `idle`（≥3 帧）、`talk`（≥3 帧）、`happy`（≥2 帧） |
| 可选状态 | `hint`、`surprised`、`wave` 等，按 NPC 剧情需要 |
| 帧率 | idle 6-8 FPS、talk 8-10 FPS、happy 10 FPS |
| 语言约束 | 除飞飞外，所有 NPC 台词只使用英语，不得出现中文 |
| 表情区分 | idle ↔ talk 嘴部/眼部有明显变化；happy 整体表情上扬 |
| 尺寸 | 单帧建议 256×256 或 320×320，按 NPC 体型调整 |

### 3.5 灵物（以 tree_spirit 为基准）

| 要素 | 规格 |
|------|------|
| 资源路径 | `assets/sprites/{spirit_name}/` |
| 分层策略 | 关键灵物采用分层合成（如 `tree_spirit` = body + eye_white + pupil） |
| 分层目的 | 眼睛/瞳孔可独立动画追踪、眨眼，不需逐帧重绘全身 |
| 透明背景 | 每层独立 PNG + Alpha |
| 状态 | 至少 `idle`（呼吸缩放）+ `awake`（被唤醒后亮起） |
| 灵光 | 灵物被唤醒时叠加金色/对应神器主色光晕，呼吸周期 1.5-2s |

---

## 4. 场景美术规范

### 4.1 第一人称背景分层规格

所有外景场景使用 `ParallaxBackground` 分层。室内场景（客栈房间、书阁）可使用单张全屏背景 + 少量独立可动物件。

| 层 | 节点示例 | z_index | motion_scale | motion_mirroring.x | 内容 |
|----|----------|---------|--------------|--------------------|------|
| Sky | `SkyLayer/Sky` | -100 | (0.1, 0.1) | 1920 | 天空 / 雾幕，1920×1080 |
| Far | `FarTreeLayer/TreesFar` | -60 | (0.35, 0.35) | 1920 | 远景树线/山脉，1920 宽，底部透明 |
| Mid | `MidTreeLayer/TreesMid` | -40 | (0.55, 0.55) | 1920 | 中景树影/建筑剪影 |
| Ground | `GroundLayer/Ground` | -20 | (0.8, 0.8) | 1920 | 地面/草地，可纵向缩放至 0.4 |
| Prop | `MidLayer/*` | 0 | — | — | 独立可动画物件（大陆、客栈遗迹、神器座） |

**约定**：
- 横向循环层统一以 `motion_mirroring.x = 1920` 为循环宽度，源图导出为 1920px 宽。
- 透明层必须保留 Alpha；需要平铺的层在 Godot 导入时开启 Repeat。
- 不要把需要运行时显隐的物件（大陆、遗迹、神器座）画进背景底图，否则镜头展示与状态控制会失效。

### 4.2 构图安全区

| 区域 | 范围 | 约束 |
|------|------|------|
| 中心安全区 | 画面中心 80% | HUD、飞飞、气泡、徽记不得遮挡；核心视觉焦点放此区 |
| 飞飞肩位 | 右下 `(0.9, 0.63)` | 背景右下不放置关键视觉文字/物件 |
| 任务追踪器 | 左上约 `(38,46)-(448,130)` | 背景左上保留留白 |
| 麦克风按钮 | 底部居中约 `(912,938)-(1008,1034)` | 背景底部居中保留留白 |
| 安静区 | 每个房间/场景保留 20-30% 留白 | 保证画面大方，不堆满道具 |

### 4.3 焦点可读性检查

每张背景交付前必须通过：
- **5 秒焦点**：5 秒内能说出画面主焦点是什么。
- **25% 缩放**：缩到 25% 大小时，主焦点物体（三扇门、书架、词灵、客房门等）仍能辨认。
- **单焦点**：每个视图只突出一个主焦点，不堆叠多个同等强度视觉元素。

---

## 5. UI 美术规范

### 5.1 对话气泡

| 类型 | 资源 | 尺寸 | 样式 | 尾巴 |
|------|------|------|------|------|
| 飞飞气泡（骨骼版） | **无贴图** — `FeifeiBody.gd` 程序化绘制 | 260×112 起，最大宽 620 | `StyleBoxFlat`：`#656565` 底 + 金色 2px 边 + 14px 圆角 | `Polygon2D` 三角尾巴，对齐头部中点 |
| ~~飞飞气泡（肩位）~~ | ~~`ui_feifei_bubble_fp.png`~~ | — | 🗑️ **已退役**（旧 `FeifeiShoulder` 专用） | — |
| 飞飞气泡（通用） | `bubble_feifei.png` | 按需 | 淡黄圆角，金色细边 | `bubble_tail.png` 拼接 |
| NPC 气泡 | `bubble_npc.png` | 按需 | 白/米色圆角，深棕细边 | 尾巴指向 NPC |

**约定**：
- 气泡圆角半径统一 12-16px。
- 文字不画进气泡图，由 `Label` / `RichTextLabel` 节点渲染，支持本地化与文本迭代。
- 气泡出现/消失使用 tween 缩放 0.6→1.0 + 淡入，时长 0.25s（骨骼版）。
- 骨骼版气泡为 `top_level`，**不随实例 scale 缩放**（否则会被缩到不可读）。

### 5.2 徽记 / 灵光反馈

| 元素 | 资源 | 尺寸 | 规范 |
|------|------|------|------|
| 神器徽记 | `badge_{scene}.png` | 150×150 | 结合区域符号（迷雾岛、飞飞光点、客栈轮廓等）；文字不画入，由 `BadgeLabel` 渲染 |
| 徽记光晕 | `badge_glow.png` | 180×180 | 金色径向光晕，呼吸周期 1.5-2s |
| 解锁动画 | `badge_unlock_effect_01~06.png` | 300×300 | 6 帧序列，10-12 FPS，金色粒子扩散 |
| 灵光反馈 | 星星条填充 | 380×30 | 橙金→魔法金渐变，从左到右填充 |

**灵光星级语义**（所有星级均为正面）：
- 1 星：灵光微亮，言灵已被听见
- 5 星：言灵清澈，神器强烈回应
- 低星级触发飞飞温柔示范，不中断对话流

### 5.3 任务追踪器

| 要素 | 规格 |
|------|------|
| 资源 | `ui_quest_tracker_bg.png`，250×120 |
| 样式 | UI 深蓝半透明面板，浅蓝边框，可加卷轴角标 |
| 文字约束 | 支持中文任务文案两行不溢出，不被装饰遮挡 |
| 位置 | 左上 `(38,46)` |
| 内容来源 | 任务文案包装为 RPG 行为（问候/介绍/请求/唤醒物件等），不写「说出某句型」 |

### 5.4 麦克风指示器

| 状态 | 资源 | 样式 |
|------|------|------|
| 待机 | `ui_mic_button_idle.png`，80×80 | 深底 + 灰色麦克风图标 |
| 录音中 | `ui_mic_button_recording.png`，80×80 | 深底 + 金色麦克风 + 呼吸光圈 |
| 隐藏 | 预加载资源 | 隐藏状态也需预加载，避免运行时卡顿 |
| pending upload 徽标 | 派生自 `MagicEchoManager.get_pending_uploads()` | UI 不维护自己的计数，只读 autoload 状态 |

**位置**：底部居中 `(912,938)-(1008,1034)`。

### 5.5 星星条

| 要素 | 规格 |
|------|------|
| 背景 | `ui_starbar_bg.png`，400×40，深蓝半透明圆角 + 金色细边框 |
| 填充 | `ui_starbar_fill.png`，380×30，橙金→魔法金渐变 |
| 位置 | 顶部居中 `(960,86)` |
| 动画 | 获得星星时从左到右填充，tween 0.4-0.6s |

### 5.6 字体建议

| 用途 | 字体 | 说明 |
|------|------|------|
| 中文 UI | 思源黑体 / 阿里巴巴普惠体 / 字魂系列儿童可读体 | 圆润、无衬线、儿童易读 |
| 英文 UI | Quicksand / Nunito / Baloo 2 | 圆角无衬线，匹配绘本风 |
| 英文教学词 | 与 UI 同体，但词灵展示可使用更圆润的手写感字体（如 Fredoka） | 保持字母形态标准，避免儿童误认 |
| 字号 | 正文 24-32px，标题 36-48px，徽记标签 28-36px | 1920×1080 基准下 |
| 行高 | 1.4-1.6 倍字号 | 中文两行不溢出 |

### 5.7 圆角 / 描边 / 阴影约定

| 元素 | 圆角半径 | 描边 | 阴影 |
|------|----------|------|------|
| 气泡 | 12-16px | 2px 金色/深棕 | 内侧柔光，无外投影 |
| 面板 | 8-12px | 1-2px 浅蓝/金色 | 可选内阴影，无重投影 |
| 按钮 | 8-12px | 1-2px 同色系深色 | 按下时内阴影 |
| 徽记 | 圆形/八角 | 2px 金色 | 金色径向光晕 |
| 图标 | 4-8px | 1px 同色系深色 | 无 |

**通用约定**：不使用纯黑描边；阴影使用同色系深色，不使用灰色投影；圆角统一在 8-16px 区间，避免混用直角与圆角。

---

## 6. 特效与动效规范

### 6.1 视觉基调

| 特效 | 色调 | 形态 | 周期 |
|------|------|------|------|
| 金色魔法光晕 | 魔法金 `#FFD700` | 径向渐变，柔边，无硬核 | 呼吸 1.5-2s |
| 雾气粒子 | 迷雾青灰 `#B3C7C7` | 大柔粒子，缓慢漂移，低 Alpha | 循环 8-12s |
| 词灵漂浮 | 词灵薄荷光 `#B8FBE7` | 小光团 ±5px 上下浮动 | 2-3s |
| 徽记解锁 | 金色 + 对应神器主色 | 6 帧粒子扩散，由内向外 | 0.5-0.6s |
| 神器微光 | 神器主色 + 金色边缘 | 小光点呼吸 + 偶发闪烁 | 1.5-2s |
| 声波光纹 | 浅金 / 浅蓝 | 同心圆扩散，Alpha 递减 | 0.8-1.2s |

### 6.2 tween 生命周期约定

参考 `CoachOverlay` 的优先级门控状态机：

| 约束 | 规范 |
|------|------|
| 可跳过 | 所有过场 tween 必须支持跳过（按任意键/点击即完成到终态） |
| 运动偏好 | 尊重用户 motion 偏好设置（若开启减少动效，tween 时长减半或改为淡入淡出） |
| 优先级门控 | 高优先级状态（如教练提示）可打断低优先级 tween；同优先级排队 |
| 生命周期 | tween 必须绑定节点生命周期，节点释放时 kill tween，避免悬挂回调 |
| 时长 | 出现 0.2-0.4s，持续 1.5-3s，消失 0.2-0.3s；过场转场 0.8s |
| 不阻塞 | UI tween 不得阻塞游戏线程；使用 `Tween` 而非 `await` 链 |
| duck 配套 | 录音相关 tween 必须与 BGM/SFX/TTS duck begin/end 成对（见 CLAUDE.md §6） |

### 6.3 粒子约定

| 约束 | 规范 |
|------|------|
| 贴图尺寸 | 单粒子贴图 ≤ 512×512 |
| Alpha | 边缘预乘检查，无黑边 |
| 数量 | 同屏粒子总数 ≤ 200，避免 overdraw |
| 层级 | 粒子层 z_index 介于 Mid 与 CanvasLayer 之间，不遮挡 UI |
| 克制 | 雾层和遮罩透明度克制，避免多层高 Alpha 全屏叠加 |

---

## 7. AI 草图 / 画师委托统一提示词模板

### 7.1 通用画风提示词（英文基准）

```text
children-friendly 2D game background, warm oriental fantasy,
clean composition, rounded shapes, soft golden magic light,
storybook style, elegant and uncluttered, readable focal point,
no horror, no dark haunted mood, no messy props, no text baked into image
```

### 7.2 场景类型变体

| 场景类型 | 在通用提示词后追加 |
|----------|---------------------|
| 海边（雾湾） | `coastal misty shore, gentle waves, soft fog veil, faint echo conch glow, dawn light` |
| 集市（长安集市） | `warm bustling oriental market street, wooden stalls, lanterns, soft crowd silhouettes in background, jade tablet motif` |
| 庭院（花灯庭院） | `courtyard with colorful lanterns, lotus pond, soft multi-color lantern glow, warm festive but calm` |
| 渡口（仙舟渡口） | `misty ferry dock at dusk, wooden jetty, moored boat, bronze compass motif, warm sunset` |
| 书阁（词灵书阁） | `teal magical library interior, floating books and pages, small glowing word spirit, dreamy but clear` |
| 观星台（岛心） | `mountaintop observatory at night, deep blue-purple starry sky, star mirror artifact, serene cosmic mood` |
| 客栈（蜃影客栈） | `warm oriental fantasy inn interior, rounded wooden shapes, three clear doors, central faint purple-gold formation light` |
| 客栈阵法房间 | `hexagonal formation room, six empty artifact seats, faint gold hope light at center, quiet and purposeful` |
| 客栈玩家房间 | `cozy child-friendly room, large bookshelf with magic light seams, wardrobe with empty reward slots` |
| 客房预告 | `quiet guest room door, faint warm light through crack, soft sound wave hint, sense of invitation not horror` |

### 7.3 小朋友吸引力检查清单

每张草图提交前自检：

- [ ] 5 秒内能说出画面主焦点是什么
- [ ] 缩到 25% 大小时，主焦点物体仍能辨认
- [ ] 画面至少有一个「想靠近看看」的发光或动态潜力点
- [ ] 没有让孩子误会可以点击的按钮式图案
- [ ] 没有过暗、过脏、过密、过尖锐的区域
- [ ] 右下飞飞肩位、左上任务面板、底部居中麦克风位有留白
- [ ] 背景中没有写死的英文/中文/教程文字
- [ ] 色彩饱和度在 50-70% 区间，魔法金面积 ≤8%
- [ ] 形状圆润无尖锐棱角
- [ ] 情绪安全温暖，无恐怖废墟/血迹/裂纹

---

## 8. 资产命名与导入约束

### 8.1 命名规范

| 类别 | 命名规则 | 示例 |
|------|----------|------|
| 背景 | `{scene}_bg.png` 或 `{scene}_{layer}.png` | `mirage_inn_hall_bg.png`、`beginning_trees_far.png` |
| 角色帧 | `{character}_{state}_{NN}.png` | `feifei_fly_01.png`、`oakley_idle_03.png` |
| UI | `ui_{element}_{state}.png` | `ui_mic_button_idle.png`、`ui_starbar_bg.png` |
| 徽记 | `badge_{scene}.png` | `badge_beginning.png` |
| 物件 | `{object}_{state}.png` | `scroll_dormant.png`、`artifact_seat_empty.png` |
| 粒子 | `{effect}_particle.png` | `inn_magic_spark.png` |
| 骨骼角色 | `{character}_part.png`（蒙皮图集）+ `{character}_frames.tres` **已废弃** | `feifei_part.png` |

**规则**：
- 全英文小写 + 下划线，不使用中文文件名、空格、连字符。
- 序号两位补零（`_01`、`_02`）。
- 状态词统一：`idle` / `talk` / `happy` / `hint` / `fly` / `walk` / `closed` / `awake` / `open` / `empty` / `recording`。

### 8.2 Godot 导入设置

| 资产类型 | Filter | Mipmaps | Repeat | Alpha | 其他 |
|----------|--------|---------|--------|-------|------|
| 背景 PNG（全屏） | On | Off | Disabled | — | 单张 ≤1920×1080 |
| 背景 PNG（横向循环层） | On | Off | Enabled | — | 宽 1920px，`motion_mirroring.x=1920` |
| 角色 / 物件 PNG | On | Off | Disabled | 保留 | 边缘预乘检查，无黑边 |
| 像素精确 UI | Off | Off | Disabled | 保留 | 按现有 UI 规范统一 |
| 粒子贴图 | On | Off | Disabled | 保留 | 边缘预乘检查 |
| 全屏遮罩（雾/眼睑） | On | Off | Disabled | 保留 | Alpha 克制，避免多层高叠加 |
| 音频 | — | — | — | — | OGG Vorbis，96-128kbps |

### 8.3 文件存放路径约定

```text
assets/
├── sprites/
│   ├── feifei/              # 飞飞
│   ├── player/              # 第一人称玩家手部
│   ├── {npc_name}/          # 各 NPC（oakley/...）
│   └── {spirit_name}/       # 各灵物（tree_spirit/...）
├── textures/
│   ├── backgrounds/         # 全屏背景、横向循环层
│   ├── objects/{scene}/     # 场景独立物件（objects/inn/、objects/fog_bay/...）
│   ├── particles/           # 粒子贴图
│   └── ui/
│       ├── fp/              # 第一人称 UI（气泡、星星条、麦克风、指南针、遮罩）
│       ├── badge_*.png      # 徽记通用资源
│       └── bubble_*.png     # 通用对话气泡
└── audio/
    ├── ambient/             # 环境音循环
    └── sfx/                 # 音效
```

**规则**：
- 不使用 `assets/textures/hotel/` 等旧版占位路径（序章已标记移除）。
- 跨场景复用资源放 `ui/` 根目录，场景专属 UI 放 `ui/fp/` 或 `ui/{scene}/`。
- 场景物件按场景分子目录，避免单目录膨胀。

---

## 9. 一致性检查清单

提交新资产前自检：

## 9.1 风格一致性
- [ ] 整体为儿童友好东方奇幻绘本风，非写实、非像素
- [ ] 形状圆润无尖锐棱角
- [ ] 色彩饱和度 50-70%，魔法金面积 ≤8%
- [ ] 不含西式魔法学院 / Spark / 精灵森林符号
- [ ] 不含恐怖、血迹、尖锐裂纹元素

## 9.2 色彩一致性
- [ ] 使用主色板或场景补充色板中的颜色
- [ ] 神器相关资产使用 §2.3 对应神器主色
- [ ] 雾气使用迷雾青灰 `#B3C7C7`，不使用纯白或纯灰
- [ ] 魔法高光使用魔法金 `#FFD700`，不使用其它金色

## 9.3 技术一致性
- [ ] 基准分辨率 1920×1080，横向循环层宽 1920px
- [ ] 透明资产 PNG + Alpha，边缘无黑边
- [ ] 命名符合 §8.1 规范（英文小写 + 下划线）
- [ ] 存放路径符合 §8.3 约定
- [ ] Godot 导入设置符合 §8.2

## 9.4 角色一致性（如适用）
- [ ] 骨骼角色（腓腓）：图集 `feifei_part.png` 部件齐全，部件边缘无黑边且可无缝拼接
- [ ] 逐帧角色（NPC）：SpriteFrames 包含必需状态（`idle`/`talk`/`happy`）
- [ ] 帧间轮廓抖动 < 2px
- [ ] 0.3 缩放下表情可辨
- [ ] NPC 台词不含中文（除飞飞外）

## 9.5 场景一致性（如适用）
- [ ] ParallaxBackground 分层符合 §4.1 z_index / motion_scale 约定
- [ ] 中心 80% 安全区无 HUD 遮挡
- [ ] 飞飞肩位 / 任务面板 / 麦克风位有留白
- [ ] 运行时需显隐的物件未画进背景底图
- [ ] 通过 5 秒焦点 + 25% 缩放检查

## 9.6 UI 一致性（如适用）
- [ ] 圆角 8-16px，无纯黑描边
- [ ] 文字由 Label 渲染，未画入图片
- [ ] 中文文案两行不溢出
- [ ] 任务文案包装为 RPG 行为，非「说出某句型」
- [ ] pending/计数类 UI 派生自 autoload 真实状态，不自维护

## 9.7 动效一致性（如适用）
- [ ] tween 可跳过，尊重 motion 偏好
- [ ] tween 绑定节点生命周期，节点释放时 kill
- [ ] 录音相关 tween 与 duck begin/end 成对
- [ ] 粒子同屏 ≤200，无多层高 Alpha 全屏叠加

---

## 相关文档

- [game-concept.md](../gdd/game-concept.md) — 世界观、六大神器、命名替换规范
- [beginning_art_assets.md](beginning_art_assets.md) — 序章美术清单
- [mirage_inn_introduction_art_assets.md](mirage_inn_introduction_art_assets.md) — 蜃影客栈美术清单
- [CLAUDE.md](../../CLAUDE.md) — Godot 客户端开发约束（录音链路、UI 状态来源等）
