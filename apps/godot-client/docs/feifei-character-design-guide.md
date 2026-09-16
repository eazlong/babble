# 灵兽角色设计操作指南

> 项目：LinguaQuest RPG（Godot 4.6 · 1920×1080 · 移动端）
> 适用：飞飞（AI 伴游灵兽）改造 + 新灵兽 NPC 批量生产
> 方法来源：ChatGPT 分享讨论（骨骼动画 + 面部局部节点 + Controller 架构）+ 本项目 Spine 蒙皮实现
> 日期：2026-09-02

---

## 0. 核心理念与总体架构

> **骨骼解决"身体怎么动"，部件解决"脸怎么动"，Controller 解决"什么时候动"。**

不要把眨眼、说话、表情全部做成骨骼动画。采用三层分离架构：

```text
Layer 1 身体层   Skeleton2D 骨骼（含 Polygon2D 蒙皮）  → idle / fly / talk / attack
Layer 2 面部层   眼睛/嘴/眉 部件状态（缩放、切换）    → blink / talk_mouth / 表情
Layer 3 驱动层   Controller 脚本（随机时序 + 状态机）  → 什么时候眨、什么时候说
```

**为什么脸不跟着骨骼走**：
- 眨眼/嘴型是离散状态（睁/半闭/闭），骨骼的连续旋转表达不了
- 贴图/多边形状态切换可批量生产，适合 AIGC 管线
- 面部层独立后，AI NPC 可以只调高层接口（`npc.speak()`、`npc.set_expression()`）

**本项目现状的关键技术点**：飞飞场景不是普通 Sprite 切换，而是
**Skeleton2D + Polygon2D 逐顶点骨骼蒙皮（Spine 风格 2D 蒙皮）**——
`Polygon2D` 节点带 `skeleton`、`bones`（逐顶点权重）、`uv`（采样 `feifei_part.png` 图集）。
骨骼旋转 → 网格形变。脸跟随头是靠**蒙皮权重**，不是节点父子关系。
这比分享讨论里的"贴图切换"方案更高级，本指南两条路线都覆盖（见 §4.4）。

---

## 1. 现状盘点（FeifeiBody 已有 / 缺失）

### 1.1 已有（`assets/scenes/components/FeifeiBody.tscn`）

| 内容 | 状态 |
|---|---|
| 骨骼树 | `body`(根) → `feature1` → `feature2`（头链）；`hand_left/right 1-4`、`leg_left/right 1-4`、`wing_left/right 1-3`、`tail → tail1` |
| 视觉 | `polygons` 容器下 14 个蒙皮 Polygon2D：head / body / wings×2 / legs×2 / eyes / mouth / hands×2 / feature / ears×2 / tail |
| 动画库 | `AnimationPlayer`：`RESET` / `fly` / `idle`（身体骨骼）；`FaceAnimationPlayer`：`talk_mouth`（口型循环） |
| 脚本 | `FeifeiBody.gd`：状态机 idle/hint/happy/talk、入场飞入、气泡（BubbleAnchor/Panel/Label/Tail，top_level 防缩放） |
| 面部层 | 眨眼由 `BlinkController.gd`（Tween 驱动 `eyes:polygon`）；口型由 `talk_mouth` 驱动 `mouth:polygon` |
| 音频 | `VoicePipeline` / `DialogueManager` autoload，`assets/test_audio/*.wav` |

### 1.2 实施状态（2026-09-15 更新）

| 项 | 状态 | 说明 |
|---|---|---|
| 眨眼 | ✅ 已实现 | `BlinkController.gd`，每 2-6 秒随机、10% 连眨，Tween 驱动 `eyes:polygon`。见 §6.2 / §6.4 |
| 动嘴（Phase 1） | ✅ 已实现 | `talk_mouth` 循环，独立 `FaceAnimationPlayer`，与身体动画并行。见 §7.1 |
| 呼吸 tween 与骨骼冲突 | ✅ 已规避 | `go_idle()` / `play_talk()` 先停 breathe tween 再播 `idle`。见 §1.3 第 4 条 |
| TTS 驱动嘴巴（Phase 3） | ⬜ 未实现 | 目前由 `talk_speaking_start()/talk_speaking_end()` 开关口型，**未做精确 lip-sync / 多嘴型**。见 §9 |
| 表情系统（Phase 2） | ⬜ 未实现 | 只有 idle/hint/happy/talk 状态机，脸没有表情切换。见 §8 |
| 多嘴型随机切换（Phase 2） | ⬜ 未实现 | 只有单一 `talk_mouth` 循环。见 §7.2 |
| 高层 NPC 接口 | ⬜ 未实现 | AI 编排仍需操作细节节点。见 §11 |
| 三尾 | ⬜ 未实现 | 设计稿三条尾巴，场景只有一组 `tail→tail1`。见 §4.3 |
| 独立 `hint` 骨骼动画 | ⬜ 未实现 | `_play_state_anim(STATE_HINT)` 目前复用 `fly` 的翅膀扇动 |
| **全部 6 个场景迁移** | ✅ 已完成（2026-09-15） | `BeginningFP` / `MirageInnIntroduction` / `MirageInnHub` / `ChangAnMarket` / `ChangAnMarketLesson02` / `WordSpiritLibraryArchiveHall` 均直接实例化 `FeifeiBody.tscn`。旧 `FeifeiShoulder.gd` / `feifei_frames.tres` / `FeifeiCompanion.tscn` 已删除 |
| 六场景腓腓落点校验 | ✅ 已完成（2026-09-16，T6 实测） | 六场景统一 `position (1656, 598)`、`scale 0.1` → 内容 bbox `x 1625..1885 / y 500..740`（屏上 260×240 px，占屏宽 13.5%），右边距 35 px、与麦克风按钮零重叠。**原值 `(1952, 648)` 是错的**：腓腓绘制内容相对实例原点有 `(+99, +22)` 偏移（骨骼根在 `-1352,184`），拿旧精灵中心当实例位置会把内容推到 `x 1921..2181` —— 1920 宽的屏幕**完全看不见**；序章 `scale 0.6` 则放大到 1561×1268 并 100% 盖住麦克风。另修 3 个控制器：场景美术建在 `CanvasLayer(layer=0)` 里，同层时 Godot 把它绘制在默认画布**之上**，会整片遮死世界空间的 `FeifeiBody` → 改 `layer = -50` |

### 1.3 必须知道的现状约束（5 条）

1. **游戏内实例 scale ≈ 0.1**（设计画布很大，骨骼根位置 `-1352,184`）。
   所有面部微调（瞳孔偏移、嘴缩放幅度）都要按**局部坐标 ×10** 的量级调参，否则肉眼不可见。
2. **现有动画的面部轨道清单（实测）**：`eyes`/`mouth` 的 `rotation/scale/position` 跟随轨道只在 `RESET` 和 `fly` 里（fly 让眼睛/嘴跟随头部）；`idle`/`talk` 是纯骨骼动画，无面部轨道。新增的 `polygon` 顶点属性与它们零重叠 → 无需删任何轨道（原"先删静态面部轨道"的计划经实测取消）。
3. **Godot 4.6 的 `AnimationPlayer` 是单播放状态**（无图层 API，`play(name)` 独占替换当前动画）→ 要并行的动画必须分给**多个 AnimationPlayer 节点**或改用 **Tween**（§2 并发修正、§6.2、§7.1）。
4. **`FeifeiBody` 是「世界空间」节点，不是 UI 层**（迁移前旧的 `FeifeiShoulder` 自己住在 `CanvasLayer(20)` 里）。两条推论：
   - 落点必须写**内容**坐标：节点原点不是内容中心，内容相对原点偏 `(+99, +22)`（scale 0.1 时）。要表达"腓腓在这里"，就把 `position` 取目标点再减去该偏移。
   - **同层里 CanvasLayer 画在默认画布之上**：任何把场景美术放进 `CanvasLayer(layer = 0)` 的控制器都会整片盖住腓腓（T6 实测：5 个场景腓腓 `visible_in_tree=true`、`modulate.a=1.00` 却一个像素都看不见）。场景美术层应取负值（本项目 `-50`），保留 `ParallaxBackground(-100)` 之下、世界内容(0) 与所有 UI(HUD 10 / dialogue 20 / overlay 30 / mic 90) 之上。
5. **呼吸 tween 与骨骼动画不能同属性**：现有代码已在 `go_idle()` 里停 breathe tween 再播 idle（注释"避免与骨骼浮动叠加"）——这是踩过的坑，新代码禁止对 `FeifeiLayer:position/scale` 再开 tween。

---

## 2. 三阶段路线

| 阶段 | 内容 | 新美术 | 工作量 |
|---|---|---|---|
| **Phase 1** ✅ 已完成（2026-09-02） | 零新资源改造：眨眼（eyes:polygon 顶点塌缩）+ 粗略动嘴（mouth:polygon 脉冲） | 无 | 0.5 天 |
| **Phase 2** | 面部部件集：眼睛 3 态 / 嘴 4 态 + 表情切换 + 三尾补全 | 1 套小部件 | 1–2 天 |
| **Phase 3** | 系统化：TTS 驱动嘴 + 高层 API + 通用 NPC 模板 + 批量生产 | 每 NPC 1 套 | 按角色数 |

先做 Phase 1：不改美术，半天让飞飞"活"过来；验收后再进 Phase 2。

> **P1 执行记录（2026-09-02，headless 自动化验证）**
> - 场景实际盘点与初版指南不同：面部轨道（eyes/mouth 的 rotation/scale/position）在 **RESET/fly** 里，**idle/talk 完全没有面部轨道**（idle/talk 期间脸相对根节点静止）
> - 关键帧技术由 `scale` 改为 **`polygon` 顶点动画**：eyes/mouth 节点 `offset=(0,0)`，几何中心距节点原点约 1200 单位（眼睛中心 (1120,216)、嘴中心 (1560,248)）——scale 方案闭眼时眼睛会竖向滑移约 20px（游戏内）；顶点动画彻底避开 pivot 问题，且与现有 rotation/scale/position 轨道零重叠，**原"删除静态面部轨道"步骤不再需要**（§5.1/§6.2/§7.1 已按实际实现修正）
> - 已实现：`blink`（0.24s 4 键 开→0.5→0.05→开）、`talk_mouth`（0.24s 循环 5 键 基础→0.65→1.2→0.65→基础）、RESET 增加 2 条 eyes/mouth polygon 初始化轨道、`BlinkController.gd`（新文件 + FeifeiLayer 下 1 个节点）、`FeifeiBody.gd` 增加 `_start/_stop_talk_mouth` 与眼/嘴基础形记录
> - 验证结果：blink/talk_mouth 各 3 个中间时刻采样与理论线性插值吻合（如 talk_mouth t=0.080 实测 factor 0.833 = 理论 0.833）；`play_talk()` 嘴动、`go_idle()` 嘴恢复基础形；BlinkController 自主调度在 5.9s 触发一次 blink（符合 2–6s 随机区间）；`godot --headless --import` rc=0
> - 踩坑备忘：① Godot 4.6 的 `AnimationPlayer.stop(keep_state: bool)` **没有按名停止参数**；② .tscn 里通用 Object 属性的 NodePath 相对 **owner（根节点）** 解析而非节点自身（BlinkController 写 `NodePath("AnimationPlayer")`，脚本另有相对路径兜底）；③ 4.6 GDScript 无 `add_animation`/`set_animation_library`/`animate_property`，程序化加动画用 `AnimationLibrary` + `get_library_list()`，本 P1 直接用 Python 文本编辑 .tscn 完成
>
> **⚠️ P1 并发修正（2026-09-02，同日二次验证发现并修复）**
> - **发现的 bug**：初版把 `blink` 与 `talk_mouth` 都放进同一个 `AnimationPlayer`。实测 Godot 4.6 的 `AnimationPlayer` 是**单播放状态（无图层 API）**，`play()` 是**独占替换**——blink 一播就把 talk_mouth 顶掉且**不会自动恢复**（说话中一眨眼嘴就永久冻结）；更隐蔽的是 `play_talk()` 里 `play("talk")` 后紧跟 `play("talk_mouth")`，**身体 talk 动画也被顶掉**（说话时身体冻结）。
> - **修复架构（三驱动器、三组互不相交属性，真并行）**：
>   | 驱动器 | 节点 | 独占属性 |
>   |---|---|---|
>   | 身体动画 | `AnimationPlayer` | 骨骼（Skeleton2D）+ fly/RESET 里 eyes/mouth 的 position/rotation/scale |
>   | 口型 | `FaceAnimationPlayer`（新增，同场景平级） | `polygons/mouth:polygon`（talk_mouth 循环） |
>   | 眨眼 | `BlinkController` 的**节点绑定 Tween**（不再用动画） | `polygons/eyes:polygon` |
> - 关键改动：`talk_mouth` 从身体库移到面部库；`blink` 动画删除，BlinkController 改用 `create_tween().tween_property(eyes, "polygon", …)` 三段（睁→0.5→0.05→睁，TRANS_LINEAR，**每段终点精确落回基础形，自恢复**，无人工干预）；RESET 里初版加的 2 条 polygon 初始化轨道**删除**（身体播放器不再碰 polygon 属性，避免与面部播放器/Tween 抢写）；`FeifeiBody.gd` 的 `_start/_stop_talk_mouth` 改到 `face_animation_player`，`_stop_talk_mouth` 只停面部播放器、只恢复嘴（不碰眼睛，避免顶掉进行中的眨眼 tween）。
> - **验证（headless 三路并发采样）**：`play_talk()` 后 `body_ap.current=talk` 且 `face_ap.current=talk_mouth` 同时成立；talk 中强制触发眨眼，0.24s 窗口内 **眼动 6/6 ∥ 嘴动 6/6 ∥ 身体动 6/6**；眨眼后眼睛精确回基础形；`go_idle()` 口型干净停止、嘴回基础形、身体切 idle。`--import` rc=0。
> - 结论：**同场景多个 AnimationPlayer 节点各自独立播放状态**，是 4.6 下让"身体 / 口型 / 眨眼"真正并行的可靠方式；单一 AnimationPlayer 内**无法**多动画并发（无图层）。

---

## 3. 角色资产生产（美术侧）

### 3.1 灵兽角色资产清单

**身体部件**（新 NPC 参考，山海经风格 22–28 层）：

| 部件 | 数量 | 关节要求 |
|---|---|---|
| 身体躯干 | 1 | 根骨骼，无关节 |
| 头 | 1 | 与躯干 1 个关节（颈） |
| 四肢 | 2–4 | 每肢 2–3 段（肩/肘/腕），Q 版可 2 段 |
| 翅膀 | 1–2 对 | **每翅 3 段**（羽根/羽中/羽尖），角度衰减摆动 |
| 尾巴 | 1–3 条 | **每尾 2–3 段**，段间相位错开 |
| 兽耳 / 角 / 特征纹 | 各 1–2 | 挂头骨，可不细分 |
| 飘带 | 0（飞飞不用） | 若用：`sin(t)` 程序化摆动，**不要**骨骼 |

飞飞特征对照（`design/gdd/spirit-coach.md`）：翅膀 ✓（场景已有 3 段）、兽耳 ✓、角 ✓（在 `feature` 部件内）、**三尾**（场景只有 1 条 2 段 → Phase 2 补，§4.3）。

**面部部件集**（核心新增，Phase 2）：

| 部件 | 状态 | 用途 |
|---|---|---|
| 眼睛（左/右） | `open` / `half` / `close` | 眨眼 |
| 眼睛（左/右） | `happy`（∩ 眯眼）/ `surprised`（● 圆睁）/ `thinking`（视线朝上） | 表情 |
| 嘴 | `idle`（∪ 微笑，已有）/ `small` / `wide` / `o`（惊讶） | 说话/惊讶 |
| 嘴（可选） | `happy`（大笑）/ `angry`（倒 V）/ `sad`（下弯） | 表情 |
| 眉（可选） | 平 / 挑 / 皱 | 情绪强化 |

**6 核心表情组合表**（眼睛 + 嘴，覆盖 95% 场景）：

| 表情 | 眼睛 | 嘴 |
|---|---|---|
| 中性 | open | idle |
| 开心 | happy 眯眼 | happy 大笑 |
| 眨眼 | close | idle |
| 惊讶 | surprised 圆睁 | o |
| 思考 | thinking 朝上 | idle |
| 鼓励 | open（可加 spark 高光） | small |

### 3.2 美术规格

- **风格锚点**（沿用 `.codex/skills/asset-gen` 规则）：现代中国神话儿童 RPG，2D 手绘感，干净轮廓，明亮配色，不偏米色；目标受众小学四年级（9–10 岁）
- **画布与尺寸**：飞飞设计画布按现有（骨骼坐标千级，游戏内 scale 0.1）；**新 NPC 建议直接按游戏内目标像素 ×10 设计**，保持一致
- **Pivot 规范**：
  - 身体部件：pivot 在**关节中心**（蒙皮时顶点权重围绕关节旋转）
  - 面部部件：pivot 在**面部中心**（眼睛在两眼正中或单眼中点，嘴在嘴中心）——scale 眨眼/动嘴依赖这一点
- **关节规范**：相邻部件重叠 **10px**，AI 生成后边缘裁 **3–5px** 去接缝，必要时 AI 补关节（重叠处重绘）
- **输出**：PNG 透明底（分割后）；蒙皮路线需要 `feifei_part.png` 这类**图集 + UV**（Spine 导出产物）

### 3.3 AIGC 生产流程（两条路线）

**路线 A：本地 asset-gen（现有 skill，推荐新 NPC 身体部件）**
```text
Gemini/Wanxiang 生成（纯色 mat 背景，禁透明）
  → rembg_matting.py 抠图
  → grid_slice.py 部件切分（或手动 PS）
  → 面部部件手修
  → 注册 docs/asset-manifest.md
  → headless Godot import 验证（项目规则：生成资产必须过验证门）
```

**路线 B：远程 ComfyUI + SAM2（精细分割，主角色用）**
```text
ComfyUI 生成/精修 → InspyrenetRembg 去背景
  → Sam2Segmentation（individual_objects，点提示）
  → ImageCropByMaskBatch 按部件裁切
  → 回 Godot 建骨骼 + 权重
```

**关键规则**：
1. Prompt 要 **solid matte background**，不要直接要透明底（AI 抠图质量差，必须 rembg/SAM2 后处理）
2. **身体部件 AIGC 生成，面部部件建议 Aseprite/PS 手绘**——面部小、状态多、要求一致，手画 1 套 30–60 分钟，比 AI 稳定得多
3. 工作文件走 `tmp/asset-gen/`，成品进 `assets/sprites/<character>/`
4. 命名：`[类型]_[名称]_[状态]`，如 `feifei_eye_l_close.png`、`feifei_mouth_wide.png`

---

## 4. Godot 角色场景搭建

### 4.1 目标结构（新 NPC 轻量版：骨骼子节点方案）

```text
SpiritNPC (CharacterBody2D)  [SpiritCharacter.gd]
├── Skeleton2D
│   └── body (Bone2D)
│       ├── head (Bone2D)
│       │   ├── head_sprite (Sprite2D)
│       │   ├── ear_l / ear_r / horn_l / horn_r (Sprite2D，head 子节点)
│       │   └── face (Node2D)                      ← 脸整体挂头骨下
│       │       ├── eye_l (Sprite2D)
│       │       ├── eye_r (Sprite2D)
│       │       └── mouth (Sprite2D)
│       ├── wing_l1 → wing_l2 → wing_l3 (每节点挂 wing_l_sprite)
│       ├── wing_r1 → wing_r2 → wing_r3
│       ├── tail_a1 → tail_a2
│       ├── tail_b1 → tail_b2
│       └── tail_c1 → tail_c2
├── AnimationPlayer        ← 身体动画 + 面部动画（分开的 anim）
├── BlinkController (Node)
├── MouthController (Node)
├── AudioStreamPlayer
└── CollisionShape2D
```

要点：
- `Sprite2D`/`Polygon2D` 是 `Bone2D` 子节点时**自动绑定**该骨骼（无需 BoneAttachment2D）
- `face` 是 `head` 的子节点 → 头骨一转，整张脸自动跟着走，**脸不会飘**
- 面部动画只改 `face` 内部节点自己的 `texture`/`scale`/`position`，不动 `head` 骨 → 两层互不冲突

### 4.2 分步操作（新 NPC）

1. `CharacterBody2D` 根节点 + 挂脚本
2. 子节点 `Skeleton2D` → 右键根骨 `Add Bone2D` 按 §4.3 层级建骨骼
3. 每个骨骼下加 `Sprite2D`，导入对应部件 PNG，调 `offset` 让 pivot 对齐关节
4. 加 `AnimationPlayer`，录 `fly`/`idle`/`talk`（§5）+ `blink`/`talk_mouth`（§6/§7）
5. 加 `BlinkController`、`MouthController` 节点，inspector 里拖入引用
6. 测试：播放 idle，观察翅膀/尾巴/头是否自然

### 4.3 骨骼层级设计（灵兽专用）

| 部位 | 段数 | 动画要点 |
|---|---|---|
| 翅膀 | 3 段/翅 | 摆角**角度衰减**：根 ±12° → 中 ±6° → 尖 ±3°，频率 0.8s |
| 尾巴 | 2–3 段/条 | 每条独立相位：尾 A 0s、尾 B -0.4s、尾 C -0.8s（关键帧整体左移实现相位差） |
| 兽耳 | 1 段（挂头骨） | 偶发大角度抖一下（2–3s 随机，15° 回弹） |
| 角 | 0 段（画在头部件里） | 不单独建骨 |
| 头 | 1 段 | 待机 ±3° 慢摆 + 身体动作的二次运动 |

**飞飞三尾补全（Phase 2）**：现有 `tail → tail1` 单链改为 3 条链 `tail_a1→tail_a2`、`tail_b1→tail_b2`、`tail_c1→tail_c2`（或 3 段），各自挂 `tail` 部件副本（PS 里旋转/翻转现有尾部件出 3 个变体），idle 动画里加 3 组 rotation 轨道并错相位。

### 4.4 进阶：Spine 风格 2D 蒙皮（飞飞现状，主角色用）

`FeifeiBody.tscn` 现有做法（Godot 4.2+ 原生支持）：

```text
Polygon2D (head/eyes/mouth/…)
├── skeleton = ../../Skeleton2D
├── bones = ["body", 权重…, "body/feature1", 权重…]   ← 逐顶点权重
├── uv = (…)                                          ← 采样 feifei_part.png
└── polygon = (…)                                     ← 局部顶点
```

- 骨骼旋转 → 顶点按权重插值形变 = 真 2D 蒙皮（等价 Spine 导出效果）
- **脸跟随头 = 蒙皮权重**（eyes/mouth 顶点权重绑在头链骨上），不需要节点父子
- 适用：主角（变形丰富）；不适用：批量 NPC（建权重成本高）
- 新建方式：Spine 编辑器制作 → 导出 → 转 Godot 场景（现有管线）；或手建 Polygon2D + 编辑器里逐顶点调权重（慢，仅小部件）

### 4.5 脸跟随身体的三种方案（选型）

| 方案 | 机制 | 适用 |
|---|---|---|
| A. face 挂 head 子节点 | 节点层级自动跟随 | 新 NPC 轻量版（默认） |
| B. `BoneAttachment2D` | 挂在 Skeleton2D 下，`bone_index` 绑定 | 视觉必须在骨骼树外（如特效锚点） |
| C. 蒙皮权重（飞飞现状） | 顶点权重绑头链 | 主角色变形 |

无论哪种，**禁止把 face 挂角色根节点**——头一转脸就"飘"了。

---

## 5. 身体动画（AnimationPlayer）

### 5.1 动画清单（分层，禁止混层）

```text
身体层（一个 anim 一个动作）：fly / idle / talk / attack / hurt
面部层（独立驱动器，只动面部属性）：talk_mouth（FaceAnimationPlayer）/ blink（BlinkController 的 Tween）
```

⚠ **两条铁律**：
1. 面部动画独占**同一属性**——P1 用 `polygons/eyes:polygon` / `polygons/mouth:polygon` 两个属性，实测无任何其他动画触碰（fly/RESET 里只有 eyes/mouth 的 rotation/scale/position 轨道，idle/talk 无面部轨道）→ 零冲突，**现有面部轨道无需删除**（原计划"删静态面部轨道"已取消，见 §2 执行记录）
2. 骨骼动画和 Tween **不要驱动同一属性**（飞飞 breathe tween 与 idle 骨骼浮动叠加的教训，代码里已有停止逻辑）

### 5.2 idle 关键帧参考（轻量版新 NPC，数值按 scale 0.1 前局部坐标）

| 轨道 | 关键帧 | 时长/插值 |
|---|---|---|
| `body:position` | (0,0) → (0,-6) → (0,0) | 1.0s loop，SINE |
| `head:rotation` | 0° → 3° → 0° → -3° → 0° | 1.6s loop，SINE |
| `wing_l1:rotation` | 0° → -12° → 0° | 0.8s loop，SINE |
| `wing_l2:rotation` | 0° → -6° → 0° | 0.8s loop（同相位） |
| `wing_l3:rotation` | 0° → -3° → 0° | 0.8s loop（同相位） |
| `wing_r*` | 镜像（+ 号） | 同上 |
| `tail_a1:rotation` | 0° → 10° → 0° | 1.2s loop，SINE |
| `tail_b1:rotation` | 0° → 12° → 0° | 1.2s loop，**整体左移 0.4s**（相位差） |
| `tail_c1:rotation` | 0° → 8° → 0° | 1.2s loop，**整体左移 0.8s** |
| `tail_a2/b2/c2` | ±5° | 随父段 |

相位差做法：把该轨道的关键帧**全部左移**（如 1.2s 循环移 -0.4s，等价于从 0.8s 处开始），loop 动画里负时间有效。

### 5.3 二次运动（natural feel 的关键）

身体动作带动头骨少量反向/延迟摆动：

```text
walk/run:
  HeadBone.rotation 序列：-2° → +1° → -1° → +2°（比身体晚半拍，幅度 ≤3°）
```

效果：跑步时头轻微晃动，眼睛嘴巴自然跟着移动，不像贴纸。幅度宁小勿大。

### 5.4 状态切换

- 状态机（已有 `FeifeiBody.gd`）：`idle / hint / happy / talk`
- 动画切换加 **0.1s 过渡**：`animation_player.play(anim, -1.0, 0.1)`
- `happy`：现有 tween 跳跃可保留（作用在根节点，但**必须先停 idle 身体动画或只用一次性动画**，避免同属性叠加）

---

## 6. 眨眼系统

### 6.1 方案对比

| 方案 | 新资源 | 效果 | 适用 |
|---|---|---|---|
| A'. `eyes:polygon` 顶点塌缩 | 无 | 顶点向眼睛中心收缩，闭眼是一条线 | ✅ Phase 1 实现（飞飞，避开 pivot 问题） |
| B. 3 态部件切换（open/half/close） | 每眼 2 张 | 闭眼有眼睑线条，更自然 | Phase 2（贴图或新 Polygon2D） |

### 6.2 Phase 1：blink（飞飞，零新资源）✅ 已实现（Tween 版）

> **实现方式修正**：blink 最初做成 AnimationPlayer 里的动画，但 4.6 单播放器 `play()` 独占替换，会把 talk_mouth / 身体 talk 顶掉（见 §2 并发修正）。最终 **blink 不用动画**，由 `BlinkController` 用节点绑定 Tween 直接驱动 `eyes:polygon`——与两个 AnimationPlayer 完全独立。下面的关键帧曲线被原样搬进了 Tween 的三段：

| 阶段 | 时长 | 眼睛状态（每顶点 y 向眼中点 cy=216 收缩，x 不变） |
|---|---|---|
| 1 | 0.08s | 睁眼 → 半闭：y' = cy + 0.5·(y−cy) |
| 2 | 0.07s | 半闭 → 闭眼：y' = cy + 0.05·(y−cy) |
| 3 | 0.09s | 闭眼 → 睁眼（原始顶点，**自恢复**） |

Tween 对 `PackedVector2Array` 属性逐顶点线性插值已实测（TRANS_LINEAR，25%/50% 采样点吻合线性理论值），等价于原 LINEAR 关键帧动画。

**为何不用 scale（pivot 实测）**：`polygons/eyes` 的 `offset=(0,0)`，顶点 bbox (880–1360, 104–328)，几何中心 (1120,216) 距节点原点约 1200 单位——scale 方案闭眼时眼睛会向原点方向滑移约 20px（游戏内），不可接受；顶点动画不动节点 transform，fly 动画的 eyes:position/rotation 跟随轨道照常工作。

### 6.3 Phase 2：3 态眼睛切换

新建 `eye_l_half`、`eye_l_close`（及右侧）部件（Aseprite 手绘，复用现有 eyes 线稿描边）。
`blink` 动画改为动画 `texture`/`visible`（Sprite 版）或两个 Polygon2D 的 visible 切换：

| 时间 | 眼睛状态 |
|---|---|
| 0.00 | open |
| 0.08 | half |
| 0.15 | close |
| 0.22 | half |
| 0.30 | open |

### 6.4 BlinkController（随机时序，推荐）✅ 已实现（Tween 版）

新建 `assets/scripts/components/BlinkController.gd`（**节点绑定 Tween 直接驱动 eyes:polygon**，不经过 AnimationPlayer——见 §6.2 的实现方式修正）：

```gdscript
## 随机眨眼控制器：每 2~6 秒随机触发一次眨眼，10% 概率连眨两次。
## 用节点绑定 Tween 直接驱动 eyes:polygon，不经过 AnimationPlayer
## （4.6 单播放器 play() 独占替换，会把口型/身体动画顶掉）。
class_name BlinkController
extends Node

@export var min_interval: float = 2.0
@export var max_interval: float = 6.0
@export var double_blink_chance: float = 0.1
@export var double_blink_gap: float = 0.35

## 眨眼三段时长（睁→半闭 0.08 / 半闭→闭 0.07 / 闭→睁 0.09）
@export var phase1_duration: float = 0.08
@export var phase2_duration: float = 0.07
@export var phase3_duration: float = 0.09
## 收缩因子（y' = cy + factor·(y−cy)，x 不变）
@export var half_closed_factor: float = 0.5
@export var closed_factor: float = 0.05
## 眼睛几何中心 y（eyes 节点 offset=(0,0)，顶点 bbox 中心 ≈216）
@export var eyes_center_y: float = 216.0

@export var eyes_polygon: Polygon2D

## 为 true 时暂停眨眼（如惊讶表情期间）
var paused: bool = false

var _base_polygon: PackedVector2Array
var _half_closed: PackedVector2Array
var _closed: PackedVector2Array

func _ready() -> void:
	# 兜底：若场景未注入 eyes_polygon（NodePath 解析失败等），按相对路径自查找
	if eyes_polygon == null:
		eyes_polygon = get_node_or_null(NodePath("../polygons/eyes")) as Polygon2D
	if eyes_polygon == null:
		push_warning("BlinkController: 找不到 eyes_polygon，眨眼禁用")
		return
	_base_polygon = eyes_polygon.polygon.duplicate()
	_half_closed = _shrink(_base_polygon, half_closed_factor)
	_closed = _shrink(_base_polygon, closed_factor)
	_schedule()

## 顶点向中心 y 收缩
func _shrink(poly: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(Vector2(v.x, eyes_center_y + factor * (v.y - eyes_center_y)))
	return out

func _schedule() -> void:
	if eyes_polygon == null:
		return
	var delay: float = randf_range(min_interval, max_interval)
	# 节点绑定 tween：节点释放时等待自动取消，无僵尸协程
	await create_tween().tween_interval(delay).finished
	if paused:
		_schedule()
		return
	_do_blink()

func _do_blink() -> void:
	if eyes_polygon == null:
		_schedule()
		return
	_do_one_blink()
	if randf() < double_blink_chance:
		await create_tween().tween_interval(double_blink_gap).finished
		_do_one_blink()
	_schedule()

func _do_one_blink() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(eyes_polygon, "polygon", _half_closed, phase1_duration).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(eyes_polygon, "polygon", _closed, phase2_duration).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(eyes_polygon, "polygon", _base_polygon, phase3_duration).set_trans(Tween.TRANS_LINEAR)
	await tw.finished
```

说明（✅ 与实际实现一致）：
- 随机 2~6s 间隔，比固定 3s 自然得多；10% 连眨增加灵动感
- **用 Tween 而非动画**：与 `AnimationPlayer`（身体）、`FaceAnimationPlayer`（口型）完全独立，`eyes:polygon` 独占归本控制器——三路真并行，谁也不顶掉谁（§2 并发修正）
- 每段 `tween_property` 终点精确落 `_base_polygon`，**眨眼自恢复**，无需人工干预；节点释放时 tween 自动取消
- 等待统一用**节点绑定 tween**（`create_tween()`）；`get_tree().create_tween()` 在节点释放后仍会回调
- 说话时**不停眨眼**（真实人边说边眨）；惊讶表情期间 `paused = true`
- 挂到 `FeifeiLayer` 下，inspector 拖入 `eyes_polygon` 引用（`polygons/eyes`）即可自启动；注意 .tscn 里通用 Object 属性的 NodePath 相对 **owner（根节点）** 解析——写 `NodePath("polygons/eyes")`，脚本里另有 `../polygons/eyes` 相对路径兜底

**零代码备选（15 分钟版）**：不写脚本，直接建 `blink_loop` 动画：长 4.5s 循环，`eyes:polygon` 轨道关键帧 `0.0 睁眼 → 4.0 睁眼 → 4.1 闭眼 → 4.24 睁眼`（顶点值同 §6.2），idle 时播放。缺点：间隔固定。验收后换 BlinkController。

---

## 7. 动嘴系统（MouthController）

### 7.1 Phase 1：talk_mouth 循环（飞飞，零新资源）✅ 已实现

动画 **`talk_mouth`**（**循环**，0.24s），轨道为 `polygons/mouth:polygon`（顶点关键帧，同样避开 pivot 问题，见 §6.2）。**放在独立的 `FaceAnimationPlayer`（同场景第二个 AnimationPlayer 节点）里**——4.6 单播放器 `play()` 独占替换，若与身体 `talk` 共用一个播放器，说话时身体会冻结（§2 并发修正）：

| 时间 | 嘴状态（每顶点 y 向嘴中心 cy=248 缩放，x 不变） |
|---|---|
| 0.00 | 基础（原始顶点） |
| 0.06 | 小嘴：y' = cy + 0.65·(y−cy) |
| 0.12 | 大嘴：y' = cy + 1.2·(y−cy) |
| 0.18 | 小嘴（0.65） |
| 0.24 | 基础（原始顶点，与循环起点一致，无缝循环） |

- **TTS 播报时身体播 `idle`**（不播 talk 身体动画，`talk` 动画保留在库中备用）：身体 `AnimationPlayer` 播 `idle`（动骨），`FaceAnimationPlayer` 播 `talk_mouth`（只动嘴），眨眼 Tween 动眼睛——三驱动器、三组互不相交属性，真正并行
- **TTS 播报驱动链路**（✅ 已实现）：对白控制器（BeginningFP / MirageInn / ChangAnMarket / ArchiveHall 四处的 `_say_text`/`_say_dialogue_line`/`_speak_flow`）在 TTS 前后调用 `talk_speaking_start()` / `talk_speaking_end()`，**仅当 `voice == "spirit"`（飞飞音，⟺ speaker=feifei）时启动口型**；其他 voice（elder/guest/object/word_spirit/young_*）只显气泡不动嘴。`show_hint()` 亦带状态同步：TALK 启动口型、其余状态停口型并恢复基础形（双保险，防口型残留）
- `talk_speaking_start/end`、`go_idle()`、`play_talk()` 在身体已在播 idle 时均不重播，避免对话行之间循环相位跳变
- 口型振幅（实测）：嘴高 86.6 本地 px 在 0.65~1.2 倍间变化 → scale 0.1 屏上 6.3~11.0 px、scale 0.45 屏上 28~49 px，清晰可见；近距离看会觉得嘴型单一，Phase 2 升级

`FeifeiBody.gd` 改造（Phase 1 最小改动，✅ 已按此实现）：

```gdscript
## P1 并发修正：口型独立播放器（不与身体 AnimationPlayer 抢播放状态）
@onready var face_animation_player: AnimationPlayer = $FaceAnimationPlayer

# _ready() 末尾：记录基础嘴型（stop 后恢复用）
	_mouth_base_polygon = mouth_polygon.polygon.duplicate()

# play_talk() 内 _play_state_anim(STATE_TALK) 之后：
	_start_talk_mouth()   # 面部播放器播 talk_mouth 循环（身体播 idle，不受影响）

# _play_state_anim(STATE_TALK)：身体播 idle（已在播 idle 则不重播，避免相位跳变）

# go_idle() 内 _play_state_anim(STATE_IDLE) 之前：
	_stop_talk_mouth()

func _start_talk_mouth() -> void:
	if face_animation_player and face_animation_player.has_animation("talk_mouth"):
		face_animation_player.play("talk_mouth")

func _stop_talk_mouth() -> void:
	# 只停面部播放器（它只含 talk_mouth 循环），不误伤身体 AnimationPlayer
	if face_animation_player:
		face_animation_player.stop()
	# 循环中途停止时最后一帧不是基础形状，恢复基础嘴型。
	# 眼睛由 BlinkController 的 Tween 自管理（每次眨眼结束都回基础形），这里不碰。
	if mouth_polygon and not _mouth_base_polygon.is_empty():
		mouth_polygon.polygon = _mouth_base_polygon
```

> ⚠ Godot 4.6 的 `AnimationPlayer.stop(keep_state: bool = false)` **没有按名停止参数**，只能整体停。口型拆到独立 `FaceAnimationPlayer` 后，`stop()` 只影响口型循环（该播放器里唯一的动画），不再需要"整体停 + 重播状态动画"的绕行，也不再需要恢复眼睛（眨眼 tween 自恢复）。

### 7.2 Phase 2：多嘴型随机切换（MouthController）

美术：Aseprite 基于现有 mouth 线稿快速画 3 个变体——`mouth_small`（小张）、`mouth_wide`（大张）、`mouth_o`（O 型，惊讶用）。场景里加 3 个 Polygon2D（同 `polygons` 容器、同蒙皮头链权重，或简单挂 head 子节点），默认隐藏。

新建 `assets/scripts/components/MouthController.gd`：

```gdscript
## 嘴型状态机：IDLE 闭嘴；TALKING 随机切嘴型（30%闭/40%小/30%大，60~120ms，
## 不做精确 lip-sync）；表情态直接换对应嘴型。切换带 0.05s 淡变避免突变。
class_name MouthController
extends Node

enum State { IDLE, TALKING, HAPPY, ANGRY, SURPRISED, SAD, THINKING }

@export var mouth_idle: Polygon2D     # 现有 polygons/mouth
@export var mouth_small: Polygon2D
@export var mouth_wide: Polygon2D
@export var mouth_o: Polygon2D        # 可选
@export var mouth_happy: Polygon2D    # 可选
@export var mouth_angry: Polygon2D    # 可选
@export var mouth_sad: Polygon2D      # 可选

var _state: State = State.IDLE
var _fade: Tween

func _ready() -> void:
	_show([mouth_idle], false)

func is_talking() -> bool:
	return _state == State.TALKING

# ---- 说话 ----
func start_talking() -> void:
	if _state == State.TALKING:
		return
	_state = State.TALKING
	_talk_loop()

func _talk_loop() -> void:
	if _state != State.TALKING:
		return
	var r: float = randf()
	var pick: Array[Polygon2D]
	if r < 0.3:
		pick = [mouth_idle]
	elif r < 0.7:
		pick = [mouth_small] if mouth_small else [mouth_idle]
	else:
		pick = [mouth_wide] if mouth_wide else [mouth_small]
	_show(pick, false)                    # 说话中硬切，节奏快
	await get_tree().create_tween().tween_interval(randf_range(0.06, 0.12)).finished
	_talk_loop()

func stop_talking() -> void:
	if _state != State.TALKING:
		return
	_state = State.IDLE
	_show([mouth_idle], true)

# ---- 表情 ----
func set_expression(e: State) -> void:
	if e == State.TALKING:
		start_talking()
		return
	if e == _state:
		return
	_state = e
	_show(_expression_parts(e), true)

func _expression_parts(e: State) -> Array[Polygon2D]:
	return match e:
		State.HAPPY: [mouth_happy] if mouth_happy else [mouth_small]
		State.ANGRY: [mouth_angry] if mouth_angry else [mouth_idle]
		State.SURPRISED: [mouth_o] if mouth_o else [mouth_wide]
		State.SAD: [mouth_sad] if mouth_sad else [mouth_idle]
		State.THINKING: [mouth_idle]
		_: [mouth_idle]

# ---- 切换（fade=true 时 0.05s 淡变）----
func _show(parts: Array[Polygon2D], fade: bool) -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	var all: Array[Polygon2D] = [mouth_idle, mouth_small, mouth_wide, mouth_o, mouth_happy, mouth_angry, mouth_sad]
	_fade = create_tween()
	for part in all:
		if part == null:
			continue
		var target: float = 1.0 if parts.has(part) else 0.0
		if fade:
			_fade.parallel().tween_property(part, "modulate:a", target, 0.05)
		else:
			part.modulate.a = target
```

**为什么不做精确 lip-sync**：随机嘴型 + 随机间隔，玩家观感已经像正常说话；精确匹配要逐帧对口型，成本 10 倍、收益 5%。AI TTS 场景下语音播放状态驱动嘴（§9）就是最佳性价比。

---

## 8. 表情系统（Phase 2）

### 8.1 表情 = 眼睛部件 + 嘴部件的组合

表情不单独做动画，而是**部件组合切换**（0.1s 淡变）：

| 表情 | 眼睛部件 | 嘴部件 | 触发场景 |
|---|---|---|---|
| neutral | open | idle | 默认 |
| happy | ∩ 眯眼 | 大笑 | 玩家答对 / 被夸奖 |
| surprised | ● 圆睁 | O 型 | 玩家答错 / 突发事件 |
| thinking | 视线朝上 | 闭嘴 | AI 生成对白中（LLM 延迟期） |
| hint | open（+spark） | 小张 | 提示台词 |

### 8.2 与 CoachOverlay 7 状态映射

`FeifeiBody` 状态机（idle/hint/happy/talk）对齐 CoachOverlay 的 7 态（idle/thinking/happy/hint/speaking/enter/exit）：

| CoachOverlay 态 | 身体动画 | 脸 |
|---|---|---|
| idle | idle | neutral + 自动眨眼 |
| thinking | idle（头微抬） | thinking（眼朝上 + 闭嘴） |
| happy | 跳跃 tween | happy（眯眼大笑），2.5s 后回 neutral |
| hint | idle | hint（encouraging） |
| speaking | talk | talk_mouth / MouthController + 正常眼（可眨眼） |
| enter / exit | fly / 淡出 | neutral |

### 8.3 ExpressionController（Phase 2 可选脚本）

把"表情 = 眼 + 嘴组合 + 自动回退"收口成一个控制器，避免调用方散乱地操作部件：

```gdscript
## 表情控制器：set_expression() 同时切换眼/嘴部件，
## 非持久表情（happy/surprised）hold 秒后自动回 neutral。
class_name ExpressionController
extends Node

@export var mouth: MouthController
@export var eye_idle: Sprite2D      # 常态 open 眼
@export var eye_happy: Sprite2D     # ∩ 眯眼
@export var eye_surprised: Sprite2D # ● 圆睁
@export var eye_thinking: Sprite2D  # 视线朝上

@export var hold_duration: float = 2.5

var _revert_tween: Tween

func set_expression(e: MouthController.State) -> void:
	if _revert_tween and _revert_tween.is_valid():
		_revert_tween.kill()
	if mouth:
		mouth.set_expression(e)
	_set_eyes(e)
	if e != MouthController.State.IDLE and e != MouthController.State.TALKING:
		_revert_tween = create_tween()
		_revert_tween.tween_interval(hold_duration)
		_revert_tween.tween_callback(set_expression.bind(MouthController.State.IDLE))

func _set_eyes(e: MouthController.State) -> void:
	var pick: Sprite2D = eye_idle
	match e:
		MouthController.State.HAPPY: pick = eye_happy
		MouthController.State.SURPRISED: pick = eye_surprised
		MouthController.State.THINKING: pick = eye_thinking
		_: pass
	for s in [eye_idle, eye_happy, eye_surprised, eye_thinking]:
		if s == null:
			continue
		var t: Tween = create_tween()
		t.tween_property(s, "modulate:a", 1.0 if s == pick else 0.0, 0.1)
```

Phase 2 过渡做法：飞飞还没有独立眼睛部件时，`thinking` 可用 `eyes:scale (0.9)` + 头骨微抬模拟；`happy` 用现有跳跃 + 嘴大笑。部件补齐后无缝换成上表。

---

## 9. 语音驱动（Phase 3：TTS → 嘴）

### 9.1 管线

```text
LLM 生成对白 → TTS 合成 wav → AudioStreamPlayer 播放
                                    ├─ 播放中 → MouthController.start_talking()
                                    └─ 播完（finished）→ stop_talking()
```

### 9.2 VoiceController

新建 `assets/scripts/components/VoiceController.gd`：

```gdscript
## TTS 播放 + 嘴驱动：播放期间嘴动，结束自动闭嘴。
## 无音频时按字数估算说话时长（fallback）。
class_name VoiceController
extends Node

@export var mouth: MouthController

@onready var _player: AudioStreamPlayer = $AudioStreamPlayer

var is_speaking: bool = false
var _fallback_tween: Tween

func speak(stream: AudioStream) -> void:
	if stream == null:
		return
	_player.stream = stream
	_player.play()
	is_speaking = true
	if mouth:
		mouth.start_talking()
	_player.finished.connect(_on_finished, CONNECT_ONE_SHOT)

## 无 TTS 时的 fallback：按字数估算（中文约 4~5 字/秒）
func speak_estimated(text: String) -> void:
	var dur: float = clampf(text.length() * 0.22, 0.6, 8.0)
	is_speaking = true
	if mouth:
		mouth.start_talking()
	_fallback_tween = create_tween()
	_fallback_tween.tween_interval(dur)
	_fallback_tween.tween_callback(stop)

func stop() -> void:
	_player.stop()
	if _fallback_tween and _fallback_tween.is_valid():
		_fallback_tween.kill()
	_on_finished()

func _on_finished() -> void:
	is_speaking = false
	if mouth:
		mouth.stop_talking()
```

### 9.3 FeifeiBody.gd 接入（Phase 3 补丁）

```gdscript
# 头部引用：
@onready var mouth_ctrl: MouthController = $MouthController
@onready var voice: VoiceController = $VoiceController

# play_talk() 改为（替换 Phase 1 的 talk_mouth 播放）：
func play_talk(audio: AudioStream = null) -> void:
	_current_state = STATE_TALK
	_stop_breathe()
	_play_state_anim(STATE_TALK)
	if audio != null:
		voice.speak(audio)               # TTS 驱动嘴
	else:
		if mouth_ctrl:
			mouth_ctrl.start_talking()    # 无音频 fallback
	state_changed.emit(STATE_TALK)

# go_idle() 内追加：
	if mouth_ctrl:
		mouth_ctrl.stop_talking()
	voice.stop()
```

接入现有链路：`DialogueManager`/`CoachClient` 取到 TTS wav（`assets/test_audio/*.wav` 或运行时合成）后 `load` 成 `AudioStreamWAV` 传给 `play_talk(stream)`。

---

## 10. 身体与脸联动原则

1. **脸必须"属于"头**：轻量版靠节点父子（face ⊂ head 骨），飞飞靠蒙皮权重。头骨动，脸自动跟——**不要在脚本里手动同步脸位置**
2. **面部动画只改局部属性**：`Mouth.scale/texture`、`Eye.texture`，绝不改 `HeadBone`；身体动画只改骨骼，绝不改脸。两层在各自坐标系运行，互不冲突
3. **动画分层**：身体 anim 和面部 anim 分开（§5.1），同时播放、属性零重叠
4. **气泡不受影响**：`BubbleAnchor` 是独立 Marker2D，表情/眨眼改动不波及气泡定位
5. **量级换算**：游戏内 scale ≈ 0.1 → 局部坐标的微调要 ×10（如瞳孔偏移 ±2px 显示 ≈ 局部 ±20）
6. **二次运动**：身体跑动时给头骨 ±2~3° 延迟摆动，脸自然跟着"晃"，消除贴纸感

---

## 11. 高层 API 与 NPC 编排

### 11.1 设计原则

AI NPC 编排层**只调高层接口**，不直接操作 Sprite/骨骼。角色再多，维护成本也不会膨胀：

```gdscript
npc.speak("你好呀，一起出发吧！")      # 气泡 + 身体 talk + 嘴动 + （可选）TTS
npc.set_expression("happy")             # 脸：眯眼 + 大笑，2.5s 回中性
npc.blink_now()                          # 立即眨一次（打招呼用）
npc.look_at(player_global_pos)           # 瞳孔/眼部件朝目标偏移
npc.play_body_animation("wave")          # 身体层单独播动作
```

### 11.2 FeifeiBody 扩展（在现有 API 上加）

现有：`show_hint() / play_talk() / play_happy() / go_idle() / play_entry_fly_in()`

| 新增/改造 | 说明 |
|---|---|
| `play_talk(audio: AudioStream = null)` | Phase 3 改造（§9.3） |
| `set_expression(e: String)` | 映射到 ExpressionController（Phase 2） |
| `blink_now()` | 调 `blink_ctrl.animation_player.play("blink")` |
| `look_at(pos: Vector2)` | 眼部件/瞳孔向目标偏移，上限 ±20 局部（显示 ≈±2px）；飞飞现状眼睛是单一多边形，先整体 eyes 偏移模拟，Phase 2 拆瞳孔后精确 |

### 11.3 通用 NPC 模板（Phase 3）

`SpiritCharacter.gd` 模板 = CharacterBody2D + Skeleton2D（§4.1 结构）+ 三个 Controller + 上面 5 个高层方法。新 NPC 制作流程：

```text
1. 复制 SpiritNPC.tscn 模板
2. 换部件 PNG（骨骼层级按角色特征增删：翅膀/尾巴/耳朵）
3. 换面部部件集（或复用通用表情部件）
4. 重录 idle/fly/talk（参考 §5.2 关键帧表）
5. blink/talk_mouth 动画直接复用（属性路径改一下）
6. 注册 docs/asset-manifest.md
```

---

## 12. 批量 NPC 与性能

- **Skeleton2D + ~20 骨骼**：单角色 CPU 开销小；蒙皮 Polygon2D 逐顶点 CPU 形变，10 个同屏无压力（移动 2D 场景）
- 背景 NPC 降级：
  - 只播 idle，**不眨眼或 6~10s 低频眨**（BlinkController 参数可调）
  - 不说话、不表情（省 MouthController 协程）
  - 远景（<40% 显示尺寸）直接换**静态 Sprite2D**（预渲染 pose），零骨骼开销
- 同角色多实例：共享 PNG/动画资源，只换 controller 参数
- 协程注意：`_talk_loop` 这类递归协程在 `stop_talking()` 后下一帧自行退出（状态判断兜底），节点出树时 `create_tween()` 随树销毁，无泄漏

---

## 13. 验收清单

**Phase 1（零新资源）**
- [ ] `blink` 动画：0.24s，eyes pivot 在眼中点（编辑器 scale 测试过）
- [ ] `fly/idle/talk` 里的静态 eyes/mouth 轨道已删
- [ ] 待机 2~6s 随机眨眼，与 idle 骨骼动画无冲突（无跳变、无回跳）
- [ ] `talk` 时嘴动，`go_idle()` 后嘴立即闭回
- [ ] 头随身体动，脸不飘（idle 头摆动时观察）
- [ ] 呼吸 tween 未与骨骼动画叠加

**Phase 2**
- [ ] 面部部件集入 `assets/sprites/feifei/`，命名合规，manifest 已注册
- [ ] 3 态眨眼切换 0.3s，有眼睑线
- [ ] 说话随机嘴型（30/40/30），间隔 60~120ms，观感自然
- [ ] 表情切换 0.1s 淡变，hold 2.5s 自动回中性
- [ ] 三尾补全：3 条链相位错开，摆动不穿帮
- [ ] 关节无白缝（翅膀最大摆角、尾巴最大摆角处检查）
- [ ] 10 个 NPC 同屏，60fps（移动端）

**Phase 3**
- [ ] TTS 播放期间嘴动，`finished` 后闭嘴
- [ ] 无音频时 `speak_estimated()` 按字数估时正常
- [ ] `npc.speak/set_expression/blink_now/look_at` 高层接口可用
- [ ] CoachOverlay 7 态与身体/脸映射全部走通

---

## 14. 常见坑 FAQ

1. **身体和脸动画混在一个 anim** → 互相覆盖，切状态跳变。必须分层（§5.1）
2. **身体 anim 里残留静态面部轨道** → blink 播完跳回旧值。删掉，面部属性交给面部 anim 独占
3. **scale 眨眼/动嘴的 pivot 不在部件中心** → 闭眼线偏移、嘴缩放漂移。先编辑器 scale 测试再录动画
4. **脸挂角色根节点** → 头动脸不动，"飘"。挂 head 子节点/权重（§4.5）
5. **AI 图不懂关节结构** → 部件接缝对不上。关节处手动重绘（重叠 10px + 裁 3-5px）
6. **关节白缝** → 最大摆角处露底。加大重叠或补关节
7. **翅膀像纸板** → 单段硬摆。3 段 + 角度衰减（§4.3）
8. **尾巴僵硬** → 各尾/各段同相位。错开相位（关键帧左移）
9. **表情突变** → 直接 visible 切换。0.05~0.1s modulate 淡变
10. **微调"不生效"** → 游戏内 scale 0.1，局部坐标要 ×10
11. **AIGC 精灵模糊** → 用动漫/卡通类模型；SDXL 通用模型出精灵偏糊
12. **让 AI 直接出透明底** → 边缘脏。要 solid matte 背景 + rembg/SAM2 后处理
13. **Tween 与骨骼动画同属性** → 幅度叠加/打架（飞飞 breathe 教训）。二选一
14. **BoneAttachment2D 放错位置** → 必须是 Skeleton2D 的子节点才生效
15. **递归协程不退出** → 循环开头判状态（`_talk_loop` 模式），节点出树 tween 随树销毁

---

## 附录 A：关键帧速查表

| 动画 | 循环 | 轨道 | 关键帧 |
|---|---|---|---|
| blink（scale 版） | 否 | `eyes:scale` | 0.00 (1,1) / 0.08 (1,0.4) / 0.15 (1,0.05) / 0.24 (1,1) |
| blink（3 态版） | 否 | `eye_*.texture` | 0.00 open / 0.08 half / 0.15 close / 0.22 half / 0.30 open |
| talk_mouth（Phase 1） | 是 0.24s | `mouth:scale` | 0.00 (1,1) / 0.06 (1,0.65) / 0.12 (1,1.2) / 0.18 (1,0.65) / 0.24 (1,1) |
| idle | 是 1.0~1.6s | `body:position` | (0,0)→(0,-6)→(0,0) SINE |
| idle | 是 | `head:rotation` | 0°→±3°→0° SINE 1.6s |
| idle | 是 0.8s | `wing_l1/2/3:rotation` | 0°→-12°/-6°/-3°→0° |
| idle | 是 1.2s | `tail_a/b/c1:rotation` | ±10°/±12°/±8°，相位 0/-0.4/-0.8s |

## 附录 B：本项目文件变更清单

**新增**
| 文件 | 阶段 |
|---|---|
| `assets/scripts/components/BlinkController.gd` | P1 |
| `assets/scripts/components/MouthController.gd` | P2 |
| `assets/scripts/components/ExpressionController.gd` | P2 |
| `assets/scripts/components/VoiceController.gd` | P3 |
| `assets/scripts/components/SpiritCharacter.gd` + `SpiritNPC.tscn` 模板 | P3 |
| `assets/sprites/feifei/`（眼 3 态 / 嘴 4 态 / 三尾部件） | P2 |

**修改**
| 文件 | 改动 |
|---|---|
| `assets/scenes/components/FeifeiBody.tscn` | 加 `blink`/`talk_mouth` 动画；删 fly/idle/talk 静态面部轨道；加 Controller 节点；（P2）面部部件 + 三尾骨骼 |
| `assets/scripts/components/FeifeiBody.gd` | `play_talk(audio)`、`go_idle()` 停嘴、`set_expression`、`blink_now`、`look_at` |
| `docs/asset-manifest.md` | 注册面部/尾巴新部件 |

**不动**：`VoicePipeline`/`DialogueManager`/`CoachClient`（只需在调用点把 wav 传给 `play_talk`）

---

*指南完。建议执行顺序：P1 四步（删静态轨道 → blink → talk_mouth → BlinkController）半天完成 → 验收 → P2。*
