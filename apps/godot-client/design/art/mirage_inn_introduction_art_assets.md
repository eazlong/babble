# MirageInnIntroduction 美术资源需求文档

**版本**: 2.0（正典：主人房开场 + 导览顺序调整）
**日期**: 2026-09-14
**所属场景**: MirageInnIntroduction（蜃影客栈首次导览 / 第三幕「大本营导览」）
**依赖文档/场景**: `assets/scenes/MirageInnIntroduction.tscn`, `assets/scripts/scenes/MirageInnIntroductionController.gd`, `assets/resources/dialogue_flows/inn_introduction.json`, `apps/godot-client/docs/adr/0001-prologue-owner-room-canon.md`

> **v2.0 正典变更**：玩家在 `BeginningFP` 主人房醒来后进入本场景，不再有“走进客栈”演出。导览第一站是主人房本身；主人房基准背景与 `BeginningFP` 共用 `mirage_inn_owner_room_bg.png`。旧 `mirage_inn_player_room_bg.png` 与旧“大厅作为第一站”的顺序退役。

---

## 总体风格指南

### 艺术风格定位

| 要素 | 规范 | 说明 |
|------|------|------|
| **整体风格** | 卡通 + 东方幻想 + 温暖客栈 | 轻松但坚定；不是恐怖废墟，也不是纯经营小屋 |
| **审美目标** | 美观大方 + 儿童吸引力 | 画面干净、层次明确、细节有惊喜；不靠杂乱装饰制造热闹 |
| **叙事氛围** | 客栈受损但仍有力量 | 神器丢失造成空缺感，阵法和词灵书阁保留希望感 |
| **信息密度** | 低负担导览 | 玩家第一次进入客栈，只需看懂三个房间和一次书架语音互动 |
| **色彩饱和度** | 中等饱和度（55-75%） | 比序章迷雾更暖，但阵法房间和词灵书阁可使用更冷的魔法色 |
| **线条特征** | 圆润木结构、柔和符文 | 儿童友好，避免尖锐破败、恐怖裂纹或压迫性暗场 |
| **魔法元素** | 金色微光 + 青绿色词灵光 | 金色用于阵法/神器线索，青绿色用于词灵与书阁 |

### 儿童吸引力原则

| 原则 | 执行要求 | 目的 |
|------|----------|------|
| **一眼可懂** | 每个视图只突出一个主焦点：大厅三门、阵法六座、书架、词灵、客房门光 | 让小朋友不用读说明也能理解当前关注点 |
| **安全温暖** | 木质圆角、暖光、柔和阴影；破损只表现为空缺和旧痕，不表现尖刺、霉斑、恐怖暗影 | 保持冒险感，但不制造害怕情绪 |
| **小惊喜** | 每个房间至少一个“会动/会亮”的细节：阵法微光、书架缝隙、漂浮书页、词灵呼吸光 | 提高探索期待，让导览不枯燥 |
| **大形清楚** | 主要物体轮廓用大块面表达，装饰纹样不抢主轮廓 | 适合儿童快速识别，也适合移动端缩放 |
| **奖励感** | 衣橱空位、词灵变清楚、第一微光都要有“以后会变多”的期待 | 把学习和收集感连接起来 |
| **克制装饰** | 不堆满道具、文字、图标；每个房间保留 20-30% 安静区域 | 保证画面大方，不像杂乱活动页 |

### 视觉禁忌

- 不使用恐怖废墟、鬼屋、阴森旅店、破败血迹、尖锐裂纹等表达。
- 不使用过度饱和的糖果色铺满全屏；重点光效可以鲜明，背景必须稳。
- 不在背景图中写死大量文字、英文单词或教程说明，避免本地化和教学词变化问题。
- 不把三扇门、书架、衣橱画成明显按钮；本场景没有点击事件。
- 不让装饰物遮挡 Feifei 气泡、任务面板、麦克风按钮和主视觉焦点。

### 色彩系统

| 色彩类型 | 色彩值 | 用途 |
|----------|--------|------|
| 客栈木棕 | `#4A3324` | 大厅、房门、主人房木结构 |
| 暖灯金 | `#F2D17A` | 大厅灯光、房门边缘、Feifei提示重点 |
| 阵法紫灰 | `#2B2638` | 阵法房间背景 |
| 神器微光金 | `#F5D25A` | 第一神器线索、阵法核心、空神器座边缘 |
| 书阁青绿 | `#214449` | 词灵书阁背景 |
| 词灵薄荷光 | `#B8FBE7` | 第一个词灵、书阁漂浮书页 |
| 客房旧绿 | `#3D3D2D` | 客房预告区域、远方旅人门影 |
| UI深底 | `#141419` | 任务面板、语音按钮背景 |

### 场景基准规格

| 要素 | 规范 | 说明 |
|------|------|------|
| **基准分辨率** | 1920x1080 (16:9) | 当前场景按全屏 `Control` 视图构建 |
| **玩家角色** | 不可见 | 通过第一人称镜头、语音和Feifei引导表达玩家存在 |
| **交互方式** | 语音推进 | 不设计点击态；唯一主动输入是玩家说“书架” |
| **Feifei层级** | CanvasLayer layer=20 | 复用 `FeifeiShoulder`，位置和气泡规格沿用序章 |
| **HUD层级** | CanvasLayer layer=10 | 任务追踪器和麦克风按钮 |
| **Overlay层级** | CanvasLayer layer=30 | 结尾淡出转场 |

---

## 1. 场景流程与视觉节点

### 1.1 导览流程

| 顺序 | 流程段 | 对应 flow_id | 视觉 | 正式美术目标 |
|------|--------|--------------|------|--------------|
| 1 | 主人房（醒来接续） | `inn_introduction.owner_room` | 复用序章主人房基准背景 | 确认这是玩家自己的房间；书柜和衣橱是主视觉；房间延续 `BeginningFP` 的同一空间 |
| 2 | 呼唤书架 | `inn_introduction.bookshelf_voice_prompt` | 麦克风按钮显示，书架可被叫醒 | 书架缝隙透出微光，明确“叫出 `bookshelf`”是唯一主动输入 |
| 3 | 词灵书阁 | `inn_introduction.word_spirit_library` | 青绿色空间 + `hello` 词灵 | 独立空间，区别于主人房；第一个词灵清楚可爱 |
| 4 | 衣橱预告 | `inn_introduction.wardrobe_preview` | 衣橱高亮 | 回到主人房；只展示空奖励位，不暗示复杂换装系统已开放 |
| 5 | 大厅三房间总览 | `inn_introduction.hall` | 三个房间入口 | 导览中段的空间总览；清楚显示左/中/右三间房 |
| 6 | 阵法房间 | `inn_introduction.formation_room` | 六个空神器座 + 微光 | 六个空位和第一点光；空缺感明确但不压抑 |
| 7 | 客房预告 | `inn_introduction.guest_room_preview` | 客房门 + “Hello...?” | 最后一个房间预告；远方的旅客与真实会话，不展开经营系统 |
| 8 | 总结转场 | `inn_introduction.summary` | 回到大厅 | 三房间关系收束，淡出进入长安西市；大厅比开场更亮一点 |

### 1.2 当前程序化占位说明

当前 `MirageInnIntroductionController.gd` 使用 `ColorRect`、`Label`、背景图和少量 cutout 动态搭建视图。正式美术交付后，建议保持“每个视图一张 1920x1080 背景 + 少量独立可动画元素”的结构：

- 主人房第一站与 `BeginningFP` 共用 `mirage_inn_owner_room_bg.png`；书柜/衣橱为独立 cutout。
- 大厅不再是第一站，而是主人房书柜/书阁/衣橱之后的空间总览。
- 不要把 Feifei、任务面板、麦克风按钮画进背景。

---

## 2. P0 必需资源

| 资源名 | 路径建议 | 尺寸 | 格式 | 用途 |
|--------|----------|------|------|------|
| `mirage_inn_hall_bg.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG-24 | 大厅总览，导览第 5 站；导览中段重新理解三房间结构 |
| `mirage_inn_formation_room_bg.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG-24 | 阵法房间背景，中心留给阵法与神器座 |
| `mirage_inn_owner_room_bg.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG-24 | 主人房基准背景（与 BeginningFP 共用）；书架/衣橱以 cutout 叠加 |
| `word_spirit_library_bg.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG-24 | 词灵书阁独立空间 |
| `mirage_inn_guest_room_bg.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG-24 | 客房预告背景，门后保留远方光感 |
| `artifact_seat_empty.png` | `assets/textures/objects/inn/` | 128x128 | PNG + Alpha | 空神器座，阵法房间使用6个 |
| `artifact_first_light.png` | `assets/textures/objects/inn/` | 96x96 | PNG + Alpha | 第一神器线索微光，可循环呼吸 |
| `bookshelf_closed.png` | `assets/textures/objects/inn/` | 420x520 | PNG + Alpha | 主人房书架默认状态 |
| `bookshelf_awake.png` | `assets/textures/objects/inn/` | 420x520 | PNG + Alpha | 玩家说“书架”后的发光状态 |
| `wardrobe_empty.png` | `assets/textures/objects/inn/` | 360x460 | PNG + Alpha | 衣橱和空奖励位 |
| `word_spirit_hello.png` | `assets/textures/objects/inn/` | 256x256 | PNG + Alpha | 第一个词灵，可用于 `hello` 教学 |
| `guest_room_distant_light.png` | `assets/textures/objects/inn/` | 420x520 | PNG + Alpha | 客房门后远方声音/光影 |

---

## 3. P1 重要资源

| 资源名 | 路径建议 | 尺寸 | 格式 | 用途 |
|--------|----------|------|------|------|
| `formation_ring.png` | `assets/textures/objects/inn/` | 720x720 | PNG + Alpha | 阵法中心圆环，支持轻微旋转或透明度脉冲 |
| `formation_lines.png` | `assets/textures/objects/inn/` | 900x900 | PNG + Alpha | 六神器座连接线，避免硬编码线条 |
| `bookshelf_open_01.png` ~ `bookshelf_open_04.png` | `assets/textures/objects/inn/` | 420x520 | PNG + Alpha | 书架打开成入口的短动画 |
| `word_spirit_glow.png` | `assets/textures/objects/inn/` | 320x320 | PNG + Alpha | 词灵外圈呼吸光 |
| `library_floating_books.png` | `assets/textures/objects/inn/` | 1400x520 | PNG + Alpha | 词灵书阁漂浮书页/书脊层 |
| `wardrobe_reward_slot_empty.png` | `assets/textures/objects/inn/` | 96x160 | PNG + Alpha | 空服装奖励槽，可复用2-4次 |
| `inn_room_dust_motes.png` | `assets/textures/particles/` | 512x512 | PNG + Alpha | 客栈内轻微尘光粒子 |
| `inn_magic_spark.png` | `assets/textures/particles/` | 256x256 | PNG + Alpha | 阵法、书架、词灵通用魔法粒子 |

---

## 4. P2 增强资源

| 资源名 | 路径建议 | 尺寸 | 格式 | 用途 |
|--------|----------|------|------|------|
| `mirage_inn_hall_parallax_back.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG + Alpha | 大厅远景分层，可做轻微镜头移动 |
| `mirage_inn_hall_parallax_front.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG + Alpha | 大厅前景梁柱/灯笼 |
| `word_spirit_library_depth_back.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG + Alpha | 词灵书阁远层 |
| `word_spirit_library_depth_front.png` | `assets/textures/backgrounds/` | 1920x1080 | PNG + Alpha | 词灵书阁前景书页 |
| `guest_voice_ripple.png` | `assets/textures/objects/inn/` | 360x180 | PNG + Alpha | 客房“Hello...?”出现时的声波光纹 |
| `artifact_seat_names_overlay.png` | `assets/textures/objects/inn/` | 900x900 | PNG + Alpha | 后续若需要标注六件神器属性，可作为叠层 |

---

## 5. 各视图详细规格

### 5.1 客栈大厅 `mirage_inn_hall_bg.png`

**画面目标**: 导览中段的空间总览，让玩家在已经认识主人房之后，重新从大厅理解三间房结构。

| 要素 | 规格 |
|------|------|
| 构图 | 左门、中门、右门横向排列；中门略高或更有阵法感 |
| 重点 | 中间阵法房间可以有弱紫金光；左边主人房更温暖；右边客房稍暗 |
| 空间感 | 木梁、灯笼、旧地板，但不要拥挤 |
| 留白 | 右下保留 Feifei 和气泡空间；左上保留任务面板 |
| 禁忌 | 不要把三个房间画成可点击按钮；这是语音推进场景 |

### 5.2 阵法房间

**画面目标**: 说明“六个神器都丢了，但阵还在”。

| 元素 | 规格 |
|------|------|
| 背景 | 暗紫灰石室或木石混合房间，中心区域干净 |
| 六个空神器座 | 六角排列，空缺感明确；座位形态统一但可有细微差异 |
| 阵法线 | 微弱发光，不应盖过空座 |
| 第一微光 | 金色小光点，位置靠近阵法中心或第一神器座，支持呼吸动画 |
| 情绪 | 不是惊吓发现，而是坚定告知；画面应安静、有使命感 |

### 5.3 主人房

**画面目标**: 这是玩家醒来的房间，也是书柜与衣橱两个成长入口；导览第一站要回答“我在自己的房间里”。

| 元素 | 规格 |
|------|------|
| 房间基调 | 暖木色、安稳、像玩家可以回来的地方 |
| 共用规范 | 使用与 `BeginningFP` 相同的 `mirage_inn_owner_room_bg.png`，保证醒来与导览是同一空间 |
| 床 | 第一人称醒来时床在镜头外；导览第一站背景不需要完整床铺 |
| 书架 | 比衣橱更显眼；可有微光缝隙暗示通往词灵书阁 |
| 衣橱 | 有 2-4 个空奖励位；不要展示太多服装，避免玩家误以为已开放 |
| 空间布局 | 书架建议在左/中区域，衣橱在右侧，符合当前实现 |
| 视觉状态 | `bookshelf_closed` 和 `bookshelf_awake` 要明显区分，但不要刺眼 |

### 5.4 词灵书阁

**画面目标**: 明确这是书架后的独立空间，不是普通书房。

| 元素 | 规格 |
|------|------|
| 背景 | 青绿色魔法空间，书页/书架可漂浮，空间边界柔和 |
| 第一个词灵 | 小而清楚，可爱但不幼稚；身上或底部显示 `hello` 相关视觉 |
| 词灵形态 | 可像发光字母、小光团、纸页精灵；必须支持后续扩展为多个词灵 |
| 文字策略 | 背景中不要硬画大量英文，避免本地化和教学词变化问题 |
| 动画建议 | 词灵轻微上下浮动，发音成功后亮度增强，拼写成功后轮廓变稳 |

### 5.5 客房预告

**画面目标**: 告诉玩家未来会有客人和会话练习，但不展开经营系统。这是导览的最后一个空间站，玩家已经先认识主人房与阵法房间，因此这里只做未来客源与会话练习的预告。

| 元素 | 规格 |
|------|------|
| 背景 | 一扇安静客房门，门后有远方微光 |
| 声音表现 | 可用浅金/浅蓝声波或门缝光表示 “Hello...?” |
| 情绪 | 有期待感，不要惊悚 |
| 信息控制 | 不展示多个NPC或复杂经营道具，避免首次导览信息过载 |

---

## 6. UI 与复用资源

本场景复用序章的 Feifei、气泡、麦克风按钮和任务面板。若尚未完成正式资源，以 `BeginningFP 美术资源清单` 中的规格为准。
- 客栈 hub 复访的出发确认走语音（对腓腓说 Let's go / 出发），不提供按钮资源，不要把出发做成可点击 UI。

| 资源 | 路径 | 本场景用途 |
|------|------|------------|
| `feifei_frames.tres` | `assets/sprites/feifei/` | Feifei飞入、肩膀待机、提示 |
| `ui_feifei_bubble_fp.png` | `assets/textures/ui/fp/` | Feifei对白气泡 |
| `ui_mic_button_idle.png` | `assets/textures/ui/fp/` | 等待玩家说“书架” |
| `ui_mic_button_recording.png` | `assets/textures/ui/fp/` | 录音中状态 |
| `ui_quest_tracker_bg.png` | `assets/textures/ui/fp/` | 当前导览任务提示 |

**UI安全区**:
- 左上 `QuestTracker` 约占 `(38,46)-(448,130)`。
- 底部居中麦克风按钮约占 `(912,938)-(1008,1034)`。
- Feifei 运行时在右下区域，气泡会跟随角色，不要在背景右下放关键视觉文字。

---

## 7. 音频资源需求

| 资源名 | 路径建议 | 格式 | 时长 | 用途 |
|--------|----------|------|------|------|
| `inn_ambient.ogg` | `assets/audio/ambient/` | OGG Vorbis | 60-120s循环 | 客栈内木屋、轻风、微弱魔法底噪 |
| `formation_room_hum.ogg` | `assets/audio/ambient/` | OGG Vorbis | 30-60s循环 | 阵法房间低频魔法声 |
| `bookshelf_awake.ogg` | `assets/audio/sfx/` | OGG Vorbis | 1-2s | 玩家说“书架”后入口醒来 |
| `library_enter.ogg` | `assets/audio/sfx/` | OGG Vorbis | 2-4s | 进入词灵书阁 |
| `word_spirit_clear.ogg` | `assets/audio/sfx/` | OGG Vorbis | 1-2s | 词灵变清楚 |
| `guest_distant_hello.ogg` | `assets/audio/sfx/` | OGG Vorbis | 1-3s | 客房门后远方声音氛围，可与TTS分离 |

## 8. 概念方向与草图提示

> 本节用于画师概念草图、AI草图或占位图迭代。最终资产仍以第2-5节的尺寸、路径和验收标准为准。

### 8.1 统一画风提示

```text
children-friendly 2D game background, warm oriental fantasy inn interior,
clean composition, rounded wooden shapes, soft golden magic light,
storybook style, elegant and uncluttered, readable focal point,
no horror, no dark haunted mood, no messy props, no text baked into image
```

### 8.2 分场景提示

| 视图 | 草图提示重点 |
|------|--------------|
| 客栈大厅 | 温暖木质大厅，三扇清楚的房门，中央门带微弱紫金阵法光，左门温馨，右门安静，画面干净大方 |
| 阵法房间 | 六角阵法房，六个空神器座，中心有一小点金色希望光，神秘但不阴森 |
| 主人房 | 儿童友好的温暖房间，大书架有魔法缝隙光，右侧衣橱有空奖励展示格，像玩家自己的小窝；与 `BeginningFP` 主人房基准背景共用同一张 owner room 背景 |
| 词灵书阁 | 青绿色魔法书阁，漂浮书页，小小发光词灵，梦幻但清楚，空间轻盈 |
| 客房预告 | 安静客房门，门缝透出远方光，浅色声波暗示“Hello”，有期待感，不恐怖 |

### 8.3 小朋友吸引力检查

每张草图提交前先做以下自检：

- 5秒内能说出画面主焦点是什么。
- 缩到 25% 大小时，三扇门、书架、词灵、客房门仍能辨认。
- 画面至少有一个“想靠近看看”的发光或动态潜力点。
- 没有让孩子误会可以点击的按钮式图案。
- 没有过暗、过脏、过密、过尖锐的区域。

---

## 9. 导入与实现约束

### 9.1 命名规范

- 背景图放入 `assets/textures/backgrounds/`。
- 客栈独立物件放入 `assets/textures/objects/inn/`。
- 粒子贴图放入 `assets/textures/particles/`。
- UI复用资源继续放入 `assets/textures/ui/fp/`。
- 文件名使用英文小写 + 下划线，不使用中文文件名。
- 主人房基准背景统一命名：`mirage_inn_owner_room_bg.png`，与 `BeginningFP` 共用。
- 旧 `mirage_inn_player_room_bg.png` 退役，不再作为新资源命名依据。

### 9.2 Godot 导入设置建议

| 类型 | 设置 |
|------|------|
| 背景 PNG | Filter On，Mipmaps Off，Repeat Disabled |
| 独立物件 PNG | Filter On，Mipmaps Off，Alpha 保留 |
| 像素精确 UI | Filter Off 或按现有 UI 规范统一 |
| 粒子贴图 | Alpha 透明，边缘预乘检查，避免黑边 |

### 9.3 替换策略

当前场景由脚本动态创建占位视图。正式资源接入时推荐分两步：

1. 先用背景图替换每个 `_build_*_view()` 的纯色背景和程序化大型形状，保持现有流程不变。
2. 再把需要动画的元素拆成独立 `TextureRect` 或 `Sprite2D`，替换 `ColorRect` 占位：神器座、第一微光、书架、词灵、客房门光。

---

## 10. 验收标准

### P0 验收

- 五个视图在 1920x1080 下均无拉伸、裁切、关键元素遮挡。
- 导览顺序必须是 主人房 → 书柜/词灵书阁 → 衣橱 → 大厅 → 阵法房间 → 客房预告 → 大厅总结；`BeginningFP` 与主人房第一站必须使用同一张 `mirage_inn_owner_room_bg.png`。
- 大厅中左/中/右三间房可一眼区分。
- 阵法房间明确显示六个空神器座，第一微光可辨。
- 主人房中书架比衣橱更突出，符合首次教学重点。
- 词灵书阁明显是独立空间，不像普通书房。
- 客房预告只有期待感，不引入复杂经营信息。
- Feifei气泡、任务面板、麦克风按钮不遮挡核心视觉。

### 动态验收

- 书架从 `closed` 到 `awake/open` 的状态变化能配合玩家说“书架”。
- 第一微光、词灵光效可循环呼吸，亮度不刺眼。
- 词灵 `hello` 成功反馈后可以明显“变清楚”。
- 结尾淡出时背景不应出现硬边或明显压缩噪点。

### 叙事验收

- 画面支持 feifei“知道神器已丢失”的设定，不表现成现场惊吓发现。
- 场景语气轻松但坚定：受损、空缺、等待修复，而不是失败或废弃。
- 首次体验只真正强调“书架/词灵书阁”，衣橱和客房保持预告级信息。
