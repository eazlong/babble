# LinguaQuest RPG 美术资源需求总表

**版本**: 1.0
**日期**: 2026-09-14
**性质**: 全局汇总清单。本文档汇总所有 per-scene 美术清单与代码/场景实测缺口，作为外包、AI 生成与排期的唯一入口。
**上游文档**:
- `art-style-guide.md` — 风格、色彩、命名、导入规范（权威总纲）
- `beginning_art_assets.md` — 序章 BeginningFP 清单
- `mirage_inn_introduction_art_assets.md` — 蜃影客栈导览清单
- `../../docs/asset-manifest.md` — 已生成资产台账与状态流转
- `../../docs/new/PRD-v1.md`、`World.md`、`Story.md`、`UI.md` — 内容与范围唯一正典

> **正典提醒**：`design/gdd/game-concept.md`、`SpiritForest` / 精灵森林 / 西式魔法学院 / 回声螺·记忆玉简等旧设定**已废弃**，不得再作为新资产依据。

---

## 0. 现状总览（实测）

统计口径：`apps/godot-client/assets/` 实测文件 + 场景/脚本引用扫描。

| 类别 | 已有 | 缺口 | 状态 |
|------|------|------|------|
| 场景背景 PNG | 5 张客栈/书阁背景 + 序章投影 | 长安西市 8 情节**全部缺失** | 🔴 阻塞 |
| 角色动画 | 腓腓已改为**骨骼动画**（`FeifeiBody.tscn`，Skeleton2D + 蒙皮） | 腓腓图集需按骨骼部件重制；其余 NPC / 玩家手部仍为逐帧 | 🟠 |

> ⚠️ **2026-09-15 架构变更（影响本表 §2.1）**：腓腓不再使用逐帧 `SpriteFrames`。
> `feifei_frames.tres` 与 `FeifeiShoulder.gd` **已废弃**，现行实现是
> `assets/scenes/components/FeifeiBody.tscn`：**Skeleton2D + Polygon2D 逐顶点蒙皮**，
> 部件采样单张图集 `feifei_part.png`。美术交付物由「逐帧 PNG 序列」变为「**一张分层部件图集**」。
> 见 `../../docs/feifei-character-design-guide.md`。

### 0.1 关键实测发现

1. **腓腓已迁移为骨骼动画（非逐帧）** — `assets/scenes/components/FeifeiBody.tscn` 为 Skeleton2D + 14 个蒙皮 Polygon2D，采样图集 `feifei_part.png`（2048×2048）。动画由三路并行驱动：`AnimationPlayer`（`RESET`/`fly`/`idle`）、`FaceAnimationPlayer`（`talk_mouth` 口型）、`BlinkController.gd`（Tween 眨眼，每 2-6 秒）。旧的 `feifei_frames.tres` 仍在磁盘上但其帧数据为空，**已无有效引用价值**。
2. **玩家手部无帧** — `assets/resources/player_sprite_frames.tres` 的 `idle` / `walk` 均为 `"frames": []`；这部分**仍为逐帧**，需求不变。
3. **项目内没有任何音频文件** — `assets/audio/` 与 `assets/resources/audio/` 仅有 `AUDIO_PLACEHOLDERS.txt`，且该文件指向已不存在的 `design/art/spirit_forest_art_assets.md`。
4. **长安西市（第一学期主线，8 情节）零美术** — `ChangAnMarketController.gd` 用 `ColorRect` + `Label` 程序化绘制两个视图（`_build_market_view` / `_build_inn_review_view`），角色为纯色方块卡片。
5. **归卷厅（现主场景）零美术** — `WordSpiritLibraryArchiveHallController.gd` 程序化绘制背景、三层字母岩壁、石碑、拼写槽（均为 `ColorRect`）。
6. **`MirageInnHub.tscn` 残留 6 个无贴图空节点** — `FarTreeLayer/TreesFar`、`MidTreeLayer/TreesMid`、`GroundLayer/Ground` 为旧序章视差结构，已无 texture 赋值。
7. **音频调用链是断的** — `RewardAnimation.gd:152` 调用 `_audio_manager.play_sfx("badge_unlock")`，而 `AudioManager.play_sfx()` 签名要求 `AudioStream`；既无资源也无注册表。
| 场景物件 Props | 客栈 8 件 | 客栈 P1/P2 共 14 件；长安全套 | 🟠 |
| UI | 旧版星星条/麦克风/指南针等 11 件 | 新国风「天机卷轴 + 聚气灵石」整套 | 🟠 |
| 音频 | **0 个文件** | BGM/环境音/SFX 全部 | 🔴 阻塞 |
| 词灵 | 仅 `word_spirit_hello.png` | 数据库 16 个词灵无美术字段、无图 | 🟠 |
| 神器 | 仅空座 + 第一微光 | 六神器本体（东皇钟等） | 🟠 |
| 字体 | STHeiti 黑体（55MB） | 国风标题体、英文无衬线体 | 🟡 |

---

## 1. 优先级定义

| 优先级 | 定义 | 判定标准 |
|--------|------|----------|
| **P0** | 阻塞当前可玩闭环 | 缺失会导致占位方块上屏或功能无声 |
| **P1** | 影响表现质量与教学反馈 | 缺失时功能可用但体验降级 |
| **P2** | 增强与打磨 | 排期富余时制作 |

---

## 2. 角色美术需求

### 2.1 腓腓 / 小飞猫（P0 — 骨骼动画）

> 唯一可说中文的角色，全程陪伴，出现频率最高。
> **实现已由逐帧 SpriteFrames 改为骨骼动画**（`FeifeiBody.tscn`），
> 因此本节需求是「**维护现有图集 + 补骨骼动画**」，**不是**「生产逐帧序列」。

| 资源 | 路径 | 规格 | 状态 |
|------|------|------|------|
| 蒙皮部件图集 | `assets/sprites/feifei/feifei_part.png` | 2048×2048 透明图集，14 个部件 | 🟠 已在用，需按骨骼部件验收（边缘无黑边、可无缝拼接） |
| 骨骼场景 | `assets/scenes/components/FeifeiBody.tscn` | Skeleton2D + 14 蒙皮 Polygon2D | ✅ 已实现 |
| 身体动画 | `AnimationPlayer`：`RESET` / `fly` / `idle` | 骨骼关键帧 | 🟠 已有基础；`hint` 复用 `fly`，**无独立 hint 动画** |
| 口型动画 | `FaceAnimationPlayer`：`talk_mouth` | 循环驱动 `mouth:polygon` | ✅ 已实现 |
| 眨眼 | `BlinkController.gd`（Tween 驱动 `eyes:polygon`） | 每 2-6 秒，10% 连眨 | ✅ 已实现 |
| 常驻光晕 | `assets/sprites/feifei/feifei_glow.png` | 140×140 PNG+Alpha | ⬜ 未制作 |
| 参考基准图 | `assets/sprites/feifei/feifei_reference.png` | 256×256 | ⬜ manifest 中标 `planned` |
| ~~`feifei_frames.tres`~~ | ~~`assets/sprites/feifei/`~~ | — | 🗑️ **已废弃**（帧数据为空，无引用价值） |

**骨骼规格**（据 `art-style-guide.md` §3.2、`feifei-character-design-guide.md`）：
- 骨骼树：`body`(根) → `feature1` → `feature2`（头链）；`hand_left/right 1-4`、`leg_left/right 1-4`、`wing_left/right 1-3`
- 部件：head / body / wings×2 / legs×2 / eyes / mouth / hands×2 / feature / ears×2 / tail
- 游戏内 `scale ≈ 0.1`，骨骼根位置 `(-1352, 184)`
- 三路驱动器互不相交、可并行：`AnimationPlayer`（骨骼）/ `FaceAnimationPlayer`（口型）/ `BlinkController`（眨眼）
- ⚠️ Godot 4.6 `AnimationPlayer` 是**单播放状态**，口型与眨眼不得复用身体播放器

**待补骨骼动画（P1）**：`hint` 目前复用 `fly` 的翅膀扇动；若要让「提示」状态有独立表演，需新增骨骼动画轨。`happy` 由脚本 tween 模拟（跳跃 + 1.3× 缩放），非骨骼动画。

> ✅ **迁移已完成（2026-09-15）**：`MirageInnIntroduction`、`MirageInnHub`、`ChangAnMarket`、`ChangAnMarketLesson02`、`WordSpiritLibraryArchiveHall` 五个场景已从 `FeifeiShoulder` 迁移到 `FeifeiBody` 实例；旧 `FeifeiShoulder.gd` / `feifei_frames.tres` / `FeifeiCompanion.tscn` 已删除。
>
> ⚠️ **待视觉校验（未经运行验证）**：五个场景的腓腓实例统一设为 `position (1952, 648)`、`scale 0.1`。
> 该值由「旧肩膀精灵中心 `(1828, 628)`」+「骨骼角色静止中心（碰撞胶囊中心 `(-1240, -200)`）」按 `scale 0.1` 反推得出，
> **未在 Godot 中渲染验证**（本机无法启动 Godot）。首次在编辑器中打开这五个场景时请确认腓腓落点与大小，按需微调这两行。
> 另注：迁移后腓腓由 `CanvasLayer(20)` 变为世界空间 `Node2D`（与 `BeginningFP` 一致），
> 因此**渲染层级位于 HUD(layer 10) 之下**——这与 `art-style-guide.md` 旧版「Feifei 高于 HUD」的描述相反，属有意的统一。

### 2.2 第一人称玩家手部（P1）

| 资源 | 路径 | 规格 | 状态 |
|------|------|------|------|
| 玩家手部帧 | `assets/sprites/player/player_hands_{state}_{NN}.png` | PNG+Alpha | 🔴 待制作 |
| SpriteFrames | `assets/resources/player_sprite_frames.tres` | `idle`(4帧)/`talk`(3帧)/`walk`(6帧) | 🟠 资源为空，需填帧 |

**约束**：仅手部/随身道具，**不可见全身**；仅在递交物品、抬手示意时出现，不常驻。

### 2.3 NPC（P0 长安西市 / P1 客栈）

> 当前项目**没有任何 NPC 立绘**。命名规范 `{npc}_{state}_{NN}.png`，必需 `idle`(≥3帧)/`talk`(≥3帧)/`happy`(≥2帧)，单帧 256×256 或 320×320。
> **语言约束**：除腓腓外所有 NPC 台词只用英语，不得出现中文。

| NPC | 设定 | 路径 | 优先级 | 状态 |
|-----|------|------|--------|------|
| 阿菱 | 同修伙伴（女孩） | `assets/sprites/aling/` | P0 | ⬜ 未制作 |
| 昊然 | 同修伙伴（男孩） | `assets/sprites/haoran/` | P0 | ⬜ 未制作 |
| 天机阁执事 | 入城登记，指令清晰 | `assets/sprites/tianji_clerk/` | P0 | ⬜ 未制作 |
| 白泽化身 | 威严讲理的白发老者，主线关键 | `assets/sprites/baize/` | P0 | ⬜ 未制作 |
| 西市胡商 | 热情、语速较快 | `assets/sprites/hu_merchant/` | P0 | ⬜ 未制作 |
| 小货郎 | 市井叫卖 | `assets/sprites/peddler/` | P1 | ⬜ 未制作 |
| 客栈掌柜 | 温和礼貌 | `assets/sprites/innkeeper/` | P1 | ⬜ 未制作 |
| 迷失凡人旅者 | 焦急、气喘（情节 7） | `assets/sprites/lost_traveler/` | P1 | ⬜ 未制作 |
| 茶馆评书先生 | 叙事性强 | `assets/sprites/storyteller/` | P2 | ⬜ 未制作 |
| 云游道人 / 扫地老僧 | 语速慢、带比喻 | `assets/sprites/wandering_daoist/` | P2 | ⬜ 未制作 |
| 西域使节 / 龙族使者 | 正式、讲究礼节 | `assets/sprites/envoy/` | P2 | ⬜ 未制作 |

> `assets/sprites/oakley/` 在旧规范中作为 NPC 基准示例，属已废弃设定，**不制作**。

### 2.4 词灵（P1）

`assets/data/spirits/spirit_database.json` 含 16 个词灵，**均无美术字段、无对应图片**；当前只有 `word_spirit_hello.png`。

| 稀有度 | 词灵 | 数量 | 建议规格 |
|--------|------|------|----------|
| common | 阳光 / 雨水 / 面包 / 米饭 / 小猫 / 书本 / 双手 / 光芒 | 8 | 256×256 PNG+Alpha |
| rare | 火焰 / 小鸟 / 勇气 / 星星 | 4 | 256×256 PNG+Alpha |
| legendary | 龙 / 爱 / 梦想 / 独角兽 | 4 | 320×320 PNG+Alpha |

**共用资源**：`word_spirit_glow.png`（320×320 外圈呼吸光）；`library_floating_books.png`（1400×520 漂浮书页层）。
**形态约束**：发光字母 / 小光团 / 纸页精灵，必须支持扩展为多词灵；**背景与本体不硬画大量英文**，避免本地化与教学词迭代问题。

### 2.5 神器（P1）

| 资源 | 路径 | 规格 | 状态 |
|------|------|------|------|
| 东皇钟 | `assets/textures/objects/artifacts/artifact_donghuang_bell.png` | 256×256 PNG+Alpha | ⬜ 未制作 |
| 问路司南 | `assets/textures/objects/artifacts/artifact_compass.png` | 256×256 | ⬜ 未制作 |
| 通晓玉如意 | `assets/textures/objects/artifacts/artifact_ruyi.png` | 256×256 | ⬜ 未制作 |
| 辩真明镜 | `assets/textures/objects/artifacts/artifact_mirror.png` | 256×256 | ⬜ 未制作 |
| 岁月号角 | `assets/textures/objects/artifacts/artifact_horn.png` | 256×256 | ⬜ 未制作 |
| 万象河图 | `assets/textures/objects/artifacts/artifact_hetu.png` | 256×256 | ⬜ 未制作 |
| 空神器座 | `assets/textures/objects/inn/artifact_seat_empty.png` | 128×128 | ✅ 已有 |
| 第一神器微光 | `assets/textures/objects/inn/artifact_first_light.png` | 96×96 | ✅ 已有 |
| 阵法中心圆环 | `assets/textures/objects/inn/formation_ring.png` | 720×720 | ⬜ 未制作 |
| 六座连接线 | `assets/textures/objects/inn/formation_lines.png` | 900×900 | ⬜ 未制作 |
| 神器座属性叠层 | `assets/textures/objects/inn/artifact_seat_names_overlay.png` | 900×900 | ⬜ 未制作（P2） |

---

## 3. 背景美术需求

### 3.1 蜃影客栈与词灵书阁（P0 — ✅ 基本完成）

| 资源 | 规格 | 状态 |
|------|------|------|
| `mirage_inn_owner_room_bg.png` | 2560×1600 源图 | ✅ 已有（序章与导览共用） |
| `mirage_inn_hall_bg.png` | 1920×1080 | ✅ 已有 |
| `mirage_inn_formation_room_bg.png` | 1920×1080 | ✅ 已有 |
| `mirage_inn_guest_room_bg.png` | 1920×1080 | ✅ 已有 |
| `word_spirit_library_bg.png` | 1920×1080 | ✅ 已有 |

**P1/P2 分层补充**：

| 资源 | 规格 | 优先级 | 状态 |
|------|------|--------|------|
| `mirage_inn_hall_parallax_back.png` | 1920×1080 PNG+Alpha | P2 | ⬜ |
| `mirage_inn_hall_parallax_front.png` | 1920×1080 PNG+Alpha | P2 | ⬜ |
| `word_spirit_library_depth_back.png` | 1920×1080 PNG+Alpha | P2 | ⬜ |
| `word_spirit_library_depth_front.png` | 1920×1080 PNG+Alpha | P2 | ⬜ |
| `mirage_inn_owner_room_parallax_back.png` | 1920×1080 PNG+Alpha | P2 | ⬜ |

> 🔧 **资产清理项**：`assets/textures/objects/inn/inn_no_title.png`（2848×1600）不在任何清单中，需确认保留或归档。

### 3.2 序章 BeginningFP（P0 — ✅ 基本完成）

| 资源 | 规格 | 状态 |
|------|------|------|
| `mirage_inn_owner_room_bg.png` | 1920×1080 | ✅ |
| `beginning_mist_continents.png` | 1320×220（室内魔法投影） | ✅ |
| `beginning_continent_mist_veil.png` | 1320×190 | ✅ |
| `beginning_projection_glow.png` | 1400×520 | ⬜ P1 未制作 |
| `inn_room_dust_motes.png` | 512×512 | ⬜ P1 未制作 |
| `wake_eye_open.gdshader` | shader | ✅ |

**退役资源**（文件保留，不得再被引用）：`fog.png`、`fog_mid.png`、`beginning_trees_far.png`、`beginning_trees_mid.png`、`forest_ground.png`、`beginning_mirage_inn_ruins.png`、`assets/textures/hotel/*`。

### 3.3 长安西市 — 第一学期 8 情节（P0 — 全部缺失）

> 教材基准：上教版《Explore》英语四年级上册 8 个单元，与 8 情节一一对应。
> **当前 0 张背景**，`ChangAnMarketController.gd` 两个视图全为 `ColorRect`（实测 `_build_market_view` L453-466、`_build_inn_review_view` L468-482）。

| # | 情节 | 地点 | 建议背景资源 | 规格 | 状态 |
|---|------|------|--------------|------|------|
| 1 | 雾门问居 | 长安城 · 雾门 | `changan_fog_gate_bg.png` | 1920×1080 | ⬜ |
| 2 | 灵兽归巢 | 西市坊墙与屋檐 | `changan_eaves_bg.png` | 1920×1080 | ⬜ |
| 3 | 市集清点 | 西市 · 货栈 | `changan_warehouse_bg.png` | 1920×1080 | ⬜ |
| 4 | 西市采买 | 西市 · 摊位长街 | `changan_stall_street_bg.png` | 1920×1080 | ⬜ |
| 5 | 四季怪街 | 西市最深处 | `changan_four_seasons_street_bg.png` | 1920×1080 | ⬜ |
| 6 | 仙草迷途（支线） | 曲江池畔 · 竹林仙草园 | `changan_bamboo_herb_garden_bg.png` | 1920×1080 | ⬜ |
| 7 | 迷雾突袭（限时） | 西市主街 → 幻境边缘 | `changan_mirage_edge_bg.png` | 1920×1080 | ⬜ |
| 8 | 东皇钟鸣 | 白泽居 → 市心钟楼顶 | `changan_bell_tower_bg.png` / `changan_baize_house_bg.png` | 1920×1080 ×2 | ⬜ |

**共用**：`changan_inn_review_bg.png`（午后客栈复习视图，替换 `_build_inn_review_view` 的纯色底）。
**氛围层**：`changan_mist_overlay.png`（替换 L432 的 `ColorRect(0.74,0.78,0.70,0.30)` 全屏雾罩）。

**构图约束（§4.2 安全区）**：中心 80% 留主焦点；右下腓腓肩位 `(0.9,0.63)`、左上任务面板 `(38,46)-(448,130)`、底部居中麦克风 `(912,938)-(1008,1034)` 必须留白；**不得把三扇门/书架/器物画成按钮**；**背景不写死中英文文字**。

**通用提示词**（`art-style-guide.md` §7.1）：
```text
children-friendly 2D game background, warm oriental fantasy,
clean composition, rounded shapes, soft golden magic light,
storybook style, elegant and uncluttered, readable focal point,
no horror, no dark haunted mood, no messy props, no text baked into image
```
集市变体追加：`warm bustling oriental market street, wooden stalls, lanterns, soft crowd silhouettes in background, jade tablet motif`

### 3.4 归卷厅 WordSpiritLibraryArchiveHall（P0 — 全部缺失）

> 现主场景，`WordSpiritLibraryArchiveHallController.gd` 程序化绘制（实测 L948-1055）。

| 资源 | 用途 | 规格 | 状态 |
|------|------|------|------|
| `archive_hall_bg.png` | 替换 L950 纯色底 `Color(0.14,0.12,0.18)` | 1920×1080 | ⬜ |
| `archive_letter_wall_upper.png` | 上岩壁（L955） | 1200×90 | ⬜ |
| `archive_letter_wall_middle.png` | 中岩壁（L956） | 1440×90 | ⬜ |
| `archive_letter_wall_lower.png` | 下岩壁（L957） | 1680×90 | ⬜ |
| `archive_stele_bg.png` | 中央石碑（L963） | 600×360 | ⬜ |
| `archive_slot_frame.png` | 拼写槽位框（L980 `slot_bar`） | 按需 | ⬜ |
| `ui_formation_pip_empty.png` / `_filled.png` | 8 格阵法充能（L1028） | 28×28 | ⬜ |

### 3.5 后续学期地图（P2 — 仅需概念方向）

| 学期 | 地图 | 神器 | 主题 |
|------|------|------|------|
| 第1学期 | 长安西市 | 东皇钟 | 迈出第一步的勇气 |
| 第2学期 | 苗疆竹海 | 问路司南 | 面对未知 |
| 第3学期 | 星沙绿洲 | 通晓玉如意 | 共情与委婉 |
| 第4学期 | 机关偃师城 | 辩真明镜 | 逻辑与辨析 |
| 第5学期 | 龙门漕运港 | 岁月号角 | 追溯与叙事 |
| 第6学期 | 昆仑神宫 | 万象河图 | 理解与共识 |

---

## 4. 场景物件 / Props

### 4.1 客栈（P0 ✅ / P1-P2 缺）

| 资源 | 规格 | 状态 |
|------|------|------|
| `scroll_dormant.png` / `scroll_awake.png` | 198×351 | ✅ |
| ~~`wardrobe_empty.png`~~ | 360×460 | ❌ 已删除（2026-09-23 删衣橱及其导览预告） |
| `word_spirit_hello.png` | 256×256 | ✅ |
| `guest_room_distant_light.png` | 420×520 | ✅ |
| ~~`bookshelf_open_01~04.png`~~ | — | ❌ 取消（2026-09-20 随书柜美术删除） |
| `wardrobe_reward_slot_empty.png` | 96×160 | ⬜ P1 |
| `guest_voice_ripple.png` | 360×180 | ⬜ P2 |
| `inn_magic_spark.png` | 256×256 粒子 | ⬜ P1 |
| `inn_room_dust_motes.png` | 512×512 粒子 | ⬜ P1 |

### 4.2 长安西市（P0 — 全部缺失）

| 资源 | 用途 | 规格 | 状态 |
|------|------|------|------|
| `prop_mist_gate.png` | 情节 1 雾门/城门 | 480×360 | ⬜ |
| `prop_eagle_nest.png` | 情节 2 鹰巢 | 200×200 | ⬜ |
| `prop_owl_nest.png` | 情节 2 鸮巢 | 200×200 | ⬜ |
| `prop_beehive.png` | 情节 2 蜂巢 | 200×200 | ⬜ |
| `prop_cargo_crates.png` | 情节 3 货栈货物 | 按需 | ⬜ |
| `prop_market_stall.png` | 情节 4 摊位 | 按需 | ⬜ |
| `prop_season_snow.png` / `_blossom.png` | 情节 5 左檐下雪/右檐开花 | 按需 | ⬜ |
| `prop_herb_miggu.png` / `prop_herb_zhuyu.png` | 情节 6 迷毂 / 祝余仙草 | 160×160 ×2 | ⬜ |
| `prop_ancient_locust.png` | 情节 5 古槐（白泽初遇） | 按需 | ⬜ |
| `prop_traffic_light.png` | 情节 7 红绿灯 | 按需 | ⬜ |
| `prop_donghuang_bell.png` | 情节 8 东皇钟钟体 | 384×384 | ⬜ |
| `prop_message_mirror.png` | 情节 8 传讯镜（承载 use the internet） | 按需 | ⬜ |

---

## 5. UI 美术需求

### 5.1 已有 UI（✅ 保留 — 序章/客栈复用）

`ui_starbar_bg.png`(400×40)、`ui_starbar_fill.png`(380×30)、`ui_quest_tracker_bg.png`(250×120)、`ui_mic_button_idle.png`/`_recording.png`(80×80)、`ui_compass_bg.png`(100×100)、`ui_compass_arrow.png`(60×60)、`badge_beginning.png`(150×150)、`badge_glow.png`(180×180)、`badge_unlock_effect_01~06.png`(300×300)、`ui_wake_lid_top.png`(1920×540)、`ui_wake_lid_bottom.png`(1920×540)、`ui_wake_darkness.png`(1920×1080)、`bubble_feifei.png`/`bubble_npc.png`/`bubble_tail.png`

> 🗑️ **新退役**：`ui_feifei_bubble_fp.png`(200×100) — 腓腓气泡已改由 `FeifeiBody.gd` 程序化绘制（`Panel` + `StyleBoxFlat` + `Polygon2D` 尾巴），该贴图**已无任何引用**。可归档，若要恢复贴图风格需先改回 `FeifeiBody` 实现。

### 5.2 新国风 UI（P1 — Phase 4，据 `docs/new/UI.md`）

> 现有 UI 仍为旧版「星星条 + 麦克风」结构。PRD v0.5 要求改为「模块化新国风」，这是一整套**未开工**的 UI 重制。

| 资源 | 用途 | 规格 | 优先级 | 状态 |
|------|------|------|--------|------|
| `ui_scroll_panel_bg.png` | 右侧天机卷轴底板（40% 宽） | 768×1080 | P1 | ⬜ |
| `ui_scroll_card_bg.png` | 流式卡片（从下往上滚动） | 720×160 | P1 | ⬜ |
| `ui_keyword_tag.png` | 重点词标签（`Could you please` 等） | 按需九宫格 | P1 | ⬜ |
| `ui_spirit_stone_idle.png` | 聚气灵石语音按钮 · 待机呼吸光 | 200×200 | P1 | ⬜ |
| `ui_spirit_stone_listening.png` | 聆听（水波纹/星沙涟漪） | 200×200 | P1 | ⬜ |
| `ui_spirit_stone_processing.png` | 处理中（光效向主视窗汇聚） | 200×200 | P1 | ⬜ |
| `ui_spirit_stone_success.png` | 成功（石青/竹绿短闪） | 200×200 | P1 | ⬜ |
| `ui_spirit_stone_hint.png` | 提示（琥珀金短闪） | 200×200 | P1 | ⬜ |
| `ui_voice_waveform_frame.png` | 实时波形反馈框 | 480×80 | P1 | ⬜ |
| `ui_topbar_bg.png` | 顶部状态栏（玩家/CEFR/LXP/设置） | 1920×64 | P1 | ⬜ |
| `ui_icon_settings.png` 等 status icons | 线性国风 icon 组 | 32×32 ×N | P1 | ⬜ |
| `ui_cat_bubble.png` | 小飞猫悬浮提示气泡 | 按需 | P1 | ⬜ |
| `ui_inn_order_card.png` | 客栈客人订单卡（替代错题卡） | 按需 | P1 | ⬜ |
| `ui_inn_progress_bar_bg.png` / `_fill.png` | 「聚沙成塔」客栈升级进度条 | 480×32 | P1 | ⬜ |
| `icon_shenqi_coin.png` | 蜃气币图标 | 64×64 | P1 | ⬜ |
| `icon_lxp.png` | LXP 图标 | 64×64 | P1 | ⬜ |
| `ui_theme_day_panel.png` | 日间「白露」面板（宣纸白/汝窑青） | 九宫格 | P2 | ⬜ |
| `ui_theme_night_panel.png` | 夜间「玄墨」面板（玄青/墨黑） | 九宫格 | P2 | ⬜ |

**色彩规范**：正确/鼓励 = 石青、竹绿；提示/纠正 = 琥珀金、低饱和朱砂红；语音激活 = 星沙金、浅青光。圆角 8-16px，**无纯黑描边**，文字一律由 `Label` 渲染**不画进图**。

### 5.3 徽记（P1）

| 资源 | 用途 | 规格 | 状态 |
|------|------|------|------|
| `badge_changan.png` | 长安西市完成徽记 | 150×150 | ⬜ |
| `badge_archive_hall.png` | 归卷厅徽记 | 150×150 | ⬜ |
| `badge_beginning.png` | 序章完成 | 150×150 | ✅ |
| `badge_forest.png` | 旧精灵森林 | — | 🗑️ 废弃（建议归档） |

---

## 6. 特效 / Shader / 粒子

### 6.1 Shader（✅ 已有，P1 待补）

| Shader | 用途 | 状态 |
|--------|------|------|
| `spirit_glow.gdshader` | 腓腓微光/翅膀提示光 | ✅ |
| `magic_burst.gdshader` | 迷雾退散、神器阵眼、客栈升级 | ✅ |
| `transition_wipe.gdshader` | 场景转场 | ✅ |
| `wake_eye_open.gdshader` | 睁眼遮罩 | ✅ |
| `star_trail.gdshader` | 星轨 | ✅ |
| `ambient_particle.gdshader` | 环境粒子 | ✅ |

**空目录待补**（`assets/resources/shaders/` 下 `environment/`、`shared/`、`transitions/` 均为空）：
- `environment/chaos_mist.gdshader`（混沌迷雾流动）— P1 ⬜
- `environment/four_seasons_blend.gdshader`（情节 5 四季同街过渡）— P1 ⬜
- `shared/paper_texture.gdshader`（宣纸质感，支撑新国风 UI）— P2 ⬜

### 6.2 VFX 预设（✅ 已有 `.tres`，粒子贴图部分缺）

| 资源 | 状态 |
|------|------|
| `ambient_float.tres` / `magic_activation.tres` | ✅ |
| `spirit_unlock_common/rare/legendary.tres` | ✅ |
| `particle_glow.png` / `particle_feifeile.png` | ✅ |
| `inn_magic_spark.png`（阵法/书架/词灵通用魔法粒子） | ⬜ P1 |
| `inn_room_dust_motes.png`（客栈尘光） | ⬜ P1 |
| `changan_mist_particle.png`（长安迷雾粒子） | ⬜ P1 |

**配对缺口（实测）**：`vfx_presets/` 下仅有 `.json` 而无同名 `.tres` 的：`star_collect`、`treasure_chest_unlock`；仅有 `.tres` 而无 `.json` 的：`spirit_unlock_rare`、`spirit_unlock_legendary`（`spirit_unlock_common` 两者齐全）。需补齐以统一预设加载路径 — 🟠 P1。
**孤立导入文件**：`vfx_presets/simple_glow.png.import` 存在但源图 `simple_glow.png` 已丢失，是全仓库唯一的孤立 `.import` — 🔧 需删除或补图。

**粒子约束**：单贴图 ≤512×512；同屏粒子 ≤200；边缘预乘检查无黑边。

---

## 7. 音频需求 🔴 最高缺口

> **实测：项目内 0 个音频文件。** `assets/audio/` 与 `assets/resources/audio/` 为空目录。
> 格式统一 **OGG Vorbis**，BGM/环境音 128kbps、SFX 96kbps。

### 7.1 序章 BeginningFP（P0）

| 资源 | 时长 | 用途 | 状态 |
|------|------|------|------|
| `beginning_ambient.ogg` | 60-120s 循环 | 主人房晨间底噪：木屋轻响、远处院落、低音量魔法泛音 | ⬜ |
| `magic_sparkle.ogg` | 1-3s | 腓腓出现、投影点亮、提示反馈 | ⬜ |
| `badge_unlock.ogg` | 5-8s | 徽章解锁 | ⬜ |

### 7.2 蜃影客栈 / 词灵书阁（P0）

| 资源 | 时长 | 用途 | 状态 |
|------|------|------|------|
| `inn_ambient.ogg` | 60-120s 循环 | 木屋、轻风、微弱魔法底噪 | ⬜ |
| `formation_room_hum.ogg` | 30-60s 循环 | 阵法房间低频魔法声 | ⬜ |
| ~~`bookshelf_awake.ogg`~~ | — | 说「书架」后入口醒来 | ❌ 删除（2026-09-20，入口改画卷后 0 调用点） |
| `library_enter.ogg` | 2-4s | 进入词灵书阁 | ⬜ |
| `word_spirit_clear.ogg` | 1-2s | 词灵变清楚 | ⬜ |
| `guest_distant_hello.ogg` | 1-3s | 客房门后远方声音 | ⬜ |

### 7.3 长安西市（P0）

| 资源 | 时长 | 用途 | 状态 |
|------|------|------|------|
| `changan_market_ambient.ogg` | 60-120s 循环 | 市井叫卖、人声嘈杂（做成无语言层） | ⬜ |
| `changan_bell_ring.ogg` | 2-4s | **东皇钟八响**，情节 1-8 逐次加强 | ⬜ |
| `changan_mist_surge.ogg` | 3-5s | 情节 7 迷雾突袭 | ⬜ |
| `ui_spirit_stone_listen.ogg` | 0.5-1s | 聚气灵石开始聆听 | ⬜ |
| `ui_spirit_stone_success.ogg` | 1-1.5s | 表达成功（石青/竹绿短闪） | ⬜ |
| `ui_spirit_stone_hint.ogg` | 0.5-1s | 提示（琥珀金短闪） | ⬜ |
| `celebration.ogg` | 2-3s | 奖励欢呼（`RewardAnimation.gd:156` 已调用） | ⬜ |
| `area_unlock.ogg` | 2-3s | 区域解锁（`RewardAnimation.gd:206` 已调用） | ⬜ |

> ⚠️ **代码已调用但不存在的音效**：`badge_unlock`、`celebration`、`area_unlock`。
> ⚠️ **接口缺陷**：`AudioManager.play_sfx()` 只接受 `AudioStream`，但调用方传的是字符串名。补齐音频时需同时增加「名称 → 资源路径」注册表，或改为在调用点 `preload`。

### 7.4 语音（TTS）音色设计

NPC 台词与腓腓提示由云端 TTS（ElevenLabs / F5-TTS）实时生成，**不需要预制语音文件**。但对话流已引用 7 个音色档位，**每个都需要音频设计定档**（实测 `dialogue_flows/*.json` 的 `voice` 字段）：

| voice 档位 | 归属 | 出现次数 | 音色要求 | 状态 |
|------------|------|----------|----------|------|
| `spirit` | 腓腓 / 小飞猫 | 85 | 儿童友好、温暖陪伴；**唯一可说中文**，中英比例随 CEFR 递进 | ⬜ 待定档 |
| `elder` | 白泽化身 · 长者 | 31 | 威严但讲理，语速适中，正式表达 | ⬜ 待定档 |
| `word_spirit` | 词灵 | 3 | 清亮、非人类但可爱，短促 | ⬜ 待定档 |
| `object` | 器物 / 机关 | 1 | 非人声质感 | ⬜ 待定档 |
| `guest` | 远方旅客 | 1 | 轻微距离感、温和 | ⬜ 待定档 |
| `young_female` | 阿菱 | 1 | 同龄女孩，自然口语 | ⬜ 待定档 |
| `young_male` | 昊然 | 1 | 同龄男孩，自然口语 | ⬜ 待定档 |

**共同要求**：
- 语速档位与停顿设计须让 9-10 岁儿童可懂；**中式口音不阻断任务**。
- 计划中的长安西市 NPC（胡商、执事、货郎等）尚无 `voice` 档位，新增对话流时需同步扩充上表。
- 除腓腓外，**所有 NPC 声道只输出英语**。

> 🟠 **对话流 schema 缺口**：`dialogue_flows/*.json` 目前**没有** `emotion` / `pose` / `portrait` 字段。若 NPC 立绘需随台词变表情（`idle`↔`talk`↔`happy`），需先扩展 dialogue flow schema，否则立绘帧做了也驱动不起来。

---

## 8. 字体需求

| 资源 | 用途 | 现状 | 状态 |
|------|------|------|------|
| ~~`STHeiti-Regular.ttf`~~ | ~~当前全局中文~~ | **2026-09-22 已删除**：零引用，且它只是 `STHeiti.ttc` face[0] 的单面子集 | 🗑️ 已清理 |
| `STHeiti.ttc` | **实际生效**的全局中文回退（`ChineseTheme.tres` 的 `fallbacks`；`DialogueBox.gd:54` 亦直接加载） | 55MB | ✅（体积需优化：可子集化） |
| `ChineseTheme.tres` | 全局 Theme（`project.godot` `[gui] theme/custom`） | 引用 ZCOOLXiaoWei（标题）+ Inter（正文）+ STHeiti.ttc（CJK 回退） | ✅ |
| 国风标题体（宋体/楷体风格） | 神话背景、任务卷轴标题 | — | ⬜ P1 |
| `Inter` / 现代无衬线 | 英文教学内容、字幕、系统按钮 | — | ⬜ P1 |

**规格**（`art-style-guide.md` §5.6）：正文 24-32px，标题 36-48px，徽记标签 28-36px（1920×1080 基准）；行高 1.4-1.6；**英文重点词不使用花体**，避免影响儿童识别。

---

## 9. 制作批次与排期建议

| 批次 | 内容 | 解锁的能力 | 依据 |
|------|------|------------|------|
| **第 1 批（P0 · 解除阻塞）** | ① 五个场景从 `FeifeiShoulder` 迁移到 `FeifeiBody`（骨骼）② 玩家手部帧 ③ 音频注册表 + 序章/客栈 9 个音频 | 恢复主角表现力与音频反馈 | 本文档 §2.1、§2.2、§7.1-7.2 |
| **第 2 批（P0 · 主线可玩）** | 长安西市 8 情节背景（9 张）+ 核心 NPC 立绘（阿菱/昊然/执事/白泽/胡商）+ `changan_bell_ring.ogg` | 第一学期主线脱离色块 | §3.3、§2.3、§7.3 |
| **第 3 批（P0 · 现主场景）** | 归卷厅全套背景与岩壁（7 件） | 现主场景脱离 `ColorRect` | §3.4 |
| **第 4 批（P1 · 客栈打磨）** | 客栈 P1/P2 props（14 件）+ 六神器 + 阵法圆环/连线 | 阵法房间与收集系统表现完整 | §4.1、§2.5 |
| **第 5 批（P1 · UI 重制）** | 新国风 UI 全套（天机卷轴、聚气灵石 5 态、状态栏、客栈经营 UI） | Phase 4 达成 | §5.2 |
| **第 6 批（P1 · 收集系统）** | 16 词灵 + 词灵光晕 + 漂浮书页 | 词灵书阁收集闭环 | §2.4 |
| **第 7 批（P2 · 打磨）** | 视差分层、双主题、字体、剩余 NPC/SFX | 品质提升 | §3.1、§5.2、§8 |

### 资产清理（建议同步执行，非新增）

- 🗑️ 归档已废弃：`badge_forest.png`、`assets/textures/hotel/*`、森林物件（`tree_big`/`bush_*`/`rock_*`/`flower_*`/`mushroom_*`/`stream.png`）、`fog.png`/`fog_mid.png`、`beginning_trees_far/mid.png`、`beginning_mirage_inn_ruins.png`、`mirage_inn_player_room_bg.png`、`mirage_inn_hall_bg_raw.png`
- 🔧 清理空节点：`MirageInnHub.tscn` 中 6 个无贴图的旧视差 Sprite2D
- 🔧 修复断链：`assets/audio/AUDIO_PLACEHOLDERS.txt` 指向已不存在的 `design/art/spirit_forest_art_assets.md`，需重写为指向本文档 §7
- 🔧 确认归属：`assets/textures/objects/inn/inn_no_title.png`、`assets/sprites/feifei/feifei_part_副本.png`

---

## 10. 交付验收标准

### 技术验收

| 项目 | 标准 |
|------|------|
| 分辨率 | 全屏背景 1920×1080（或等比 ≥2560×1600）；横向循环层宽 1920px |
| Alpha | 角色/物件/UI/粒子 PNG+Alpha，边缘预乘检查**无黑边** |
| 骨骼动画（腓腓） | `FeifeiBody.tscn` 含 `RESET`/`fly`/`idle`/`talk_mouth`；三路驱动器（骨骼/口型/眨眼）互不顶替 |
| 逐帧动画（NPC / 玩家手部） | SpriteFrames 含必需状态：NPC `idle`/`talk`/`happy`；玩家手部 `idle`/`talk`/`walk` |
| 命名 | 英文小写 + 下划线，序号两位补零（§8.1） |
| 路径 | 符合 `art-style-guide.md` §8.3 目录约定 |
| 导入 | 背景 Filter On / Mipmaps Off / Repeat Disabled；像素 UI Filter Off；循环层 Repeat Enabled |
| 音频 | OGG Vorbis，BGM 128kbps / SFX 96kbps |
| 性能 | 单场景纹理 <50MB；全屏遮罩不叠加多层高 Alpha |

### 风格验收（每张资产提交前自检）

- [ ] 儿童友好东方奇幻绘本风，非写实、非像素
- [ ] 形状圆润无尖锐棱角；无恐怖废墟/血迹/尖锐裂纹
- [ ] 色彩饱和度 50-70%；**魔法金 `#FFD700` 面积 ≤8%**
- [ ] 雾气用迷雾青灰 `#B3C7C7`，不用纯白/纯灰
- [ ] 5 秒内能说出主焦点；缩到 25% 主焦点仍可辨
- [ ] 右下腓腓位 / 左上任务面板 / 底部麦克风位有留白
- [ ] 背景**无写死中英文文字**（保障本地化与教学词迭代）
- [ ] 无「看起来可以点击」的按钮式图案（本作以注视 + 语音推进）

### 集成验收

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit
```

场景可见资产需逐个验证：`BeginningFP.tscn`、`MirageInnIntroduction.tscn`、`MirageInnHub.tscn`、`ChangAnMarket.tscn`、`ChangAnMarketLesson02.tscn`、`WordSpiritLibraryArchiveHall.tscn`。

---

## 相关文档

- [art-style-guide.md](art-style-guide.md) — 全局风格与命名规范（权威）
- [beginning_art_assets.md](beginning_art_assets.md) — 序章清单
- [mirage_inn_introduction_art_assets.md](mirage_inn_introduction_art_assets.md) — 客栈导览清单
- [../../docs/asset-manifest.md](../../docs/asset-manifest.md) — 已生成资产台账
- [../../docs/new/Story.md](../../docs/new/Story.md) — 8 情节与 NPC 群像
- [../../docs/new/World.md](../../docs/new/World.md) — 六学期地图与神器
- [../../docs/new/UI.md](../../docs/new/UI.md) — 新国风 UI 规格
