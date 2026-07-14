# godogen 应用于本项目的研究结论

日期：2026-07-14  
研究对象：https://github.com/htdt/godogen.git  
核对版本：`05cebffc8b10c5817e8a3db495b82e7b6004ab84`

## 结论

`godogen` 不适合直接“安装成插件”或直接 `publish.sh --force` 覆盖到本项目。它本质上是一个游戏仓库生成器：从 `godogen` 发布一套薄运行时到新游戏仓库，再由代理按引擎指南生成项目。官方 README 明确写的是 `godogen -> game repo -> game`，发布产物包含运行时 manifest、引擎指南和资产生成 skill，而不是一个 Godot 编辑器插件或 addon。来源：[README.md lines 9-22](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/README.md#L9-L22)。

对当前 `LinguaQuest RPG`，推荐只选择性吸收两部分：

- `asset-gen` 资产生成技能：用于生成小飞猫、场景背景、客栈物件、UI 图标、动画帧、GLB 参考资产。
- “运行后验证”工作流：每次改场景或资产后，用 Godot headless import、实际运行截图/录像来判断结果，而不是只看代码或编译成功。

不推荐直接采用 `godogen` 的 Godot C#/.NET 场景生成规范。本项目是 Godot 4.6 GDScript 项目，入口、autoload 和资源组织已经成型；`godogen` 的 Godot guide 明确以 Godot 4 .NET/Mono + C# 为栈，并要求 `.csproj`、`dotnet build`、C# `SceneTree` 构建 `.tscn`。来源：[engines/godot.md lines 1-16](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/engines/godot.md#L1-L16)。本项目配置显示当前项目名为 `LinguaQuest RPG`、主场景为 `res://assets/scenes/BeginningFP.tscn`、特性包含 Godot `4.6` 和 `Mobile`，autoload 已经是 `.gd` 脚本体系。来源：本项目 [project.godot](/Users/gongzuoyonghu/Documents/code/games/lauguage_game/apps/godot-client/project.godot:15)。

## godogen 能提供什么

`godogen` 支持 Godot、Bevy、Babylon.js 三类游戏生成流程。它对 Godot 的定位是 Godot 4 C#/.NET 项目，配合构建期场景生成、运行时脚本和 Jolt physics。来源：[README.md lines 24-31](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/README.md#L24-L31)。

资产生成部分是跨引擎的。`asset-gen` 支持 Gemini / xAI Grok 生成 PNG，Tripo3D 生成 GLB、rigged biped 和 retarget 动画，还支持动画 sprite 的视频抽帧、循环检测和抠图。来源：[asset-gen/SKILL.md lines 1-13](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/asset-gen/SKILL.md#L1-L13)、[lines 43-65](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/asset-gen/SKILL.md#L43-L65)。

它的运行理念是“proof over claims”：从正在运行的游戏、直播画面或录制片段判断是否完成，而不是只凭干净编译。来源：[README.md lines 29-31](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/README.md#L29-L31)、[prompts/runtime.md](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/prompts/runtime.md)。

## 本项目的适配点

### 1. 资产生成替换占位图

本项目目前已有大量占位 PNG 和动画资源，且有 `scripts/PLACEHOLDER_README.md` 记录替换路径。`asset-gen` 可以用于逐批替换这些占位资源，但要保留现有路径和尺寸约定，避免破坏 `.tres`、`.tscn` 引用。

优先级建议：

- 小飞猫：生成统一 reference，再生成 idle、happy、hint、fly 等动作帧。
- 蜃影客栈：生成 `assets/textures/hotel/` 和 `assets/textures/objects/inn/` 的背景、家具、经营物件。
- 序章/迷雾林地：替换 `assets/textures/backgrounds/`、`assets/textures/objects/` 中仍偏占位的美术。
- UI：替换 badge、bubble、mic button、starbar 等儿童端高频视觉资产。

采用规则：

- 运行产物放入现有 Godot 资源目录，例如 `assets/textures/...`、`assets/sprites/...`、`assets/resources/sprites/...`。
- 生成中间文件、参考图、失败稿放在 `tmp/asset-gen/` 或 `tmp/imagegen/`，不要放入运行期加载目录。
- 每次替换后执行 Godot reimport 或 `godot --headless --import`，再运行相关场景检查资源引用。

### 2. 生成资产清单

`asset-gen` 建议维护资产表，记录名称、描述、游戏内尺寸、路径、成本。来源：[asset-gen/SKILL.md lines 113-124](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/asset-gen/SKILL.md#L113-L124)。

本项目不建议把表放到顶层 README；更合适的位置是新增：

- `docs/asset-manifest.md`：全项目美术资产总表。
- 或按场景拆分：`docs/assets-spirit-forest.md`、`docs/assets-mirage-inn.md`。

表中至少记录：

- Godot 路径。
- 预期显示尺寸或场景用途。
- 生成模型、prompt 摘要、成本。
- 是否已导入 Godot、是否已在场景截图验证。

### 3. 动画 sprite 生产线

`asset-gen` 的 sprite 流程是 reference -> pose -> video -> extract frames -> loop-trim -> rembg。来源：[asset-gen/SKILL.md lines 43-54](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/asset-gen/SKILL.md#L43-L54)。

这适合本项目的 2D 角色和 UI 动效，尤其是：

- 小飞猫飞行、提示、鼓励反馈。
- 玩家手部/第一人称互动反馈。
- 徽章解锁、星星飞行动画、客栈经营物件反馈。

注意事项：

- `asset-gen` 指出小尺寸 sprite 直接从 1K 缩到 64px 会糊，建议显示尺寸至少 128px，或生成套图后切片。来源：[asset-gen/SKILL.md lines 31-35](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/asset-gen/SKILL.md#L31-L35)。
- 方向不可靠时只生成一个方向，在 Godot 中水平翻转，避免重复付费。来源：[asset-gen/SKILL.md lines 105-111](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/asset-gen/SKILL.md#L105-L111)。
- 本项目现有 SpriteFrames `.tres` 可以继续复用；只替换帧文件或新增 `.tres`，不要为了资产生成改核心动画系统。

### 4. 运行验证流程

`godogen` 的 Godot guide 推荐在资产变化后跑 `godot --headless --import`，再跑 Godot headless 检查项目能正常打开。来源：[engines/godot.md lines 7-12](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/engines/godot.md#L7-L12)。

本项目可以采用 GDScript 版本的验证门禁：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit
```

后续可以补一个 GDScript capture scene 或测试 runner，专门打开 `BeginningFP.tscn`、`MirageInnIntroduction.tscn`、`SpiritForest.tscn` 等关键场景，保存截图到 `screenshots/`。`godogen` 的 C# movie writer 示例不能原样照搬，但“固定帧率、短录像、看回放再判断”的原则值得采用。来源：[engines/godot.md lines 52-66](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/engines/godot.md#L52-L66)。

### 5. GLB 和导入 guardrails

如果后续为客栈、场景道具或角色试验 GLB，`godogen` 的 Godot guide 里有几条可以直接变成本项目 code review / technical art checklist：

- 打包 `.tscn` 时需要正确设置 owner chain，否则节点可能静默丢失。
- 不要递归设置已实例化 GLB / `.tscn` 子树的 owner，否则可能把导入网格内联进文本场景，导致 `.tscn` 巨大化。
- GLB 碰撞体优先用 AABB 推导出的 Box / Sphere / Capsule 等基础形状，不要直接从导入网格生成 trimesh / convex collision。
- 不要在 `assets/` 下放 `.gdignore`，否则导入器可能静默跳过资源。

来源：[engines/godot.md lines 18-50](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/engines/godot.md#L18-L50)。

## 不建议直接采用的部分

### 不要在现有项目上运行 publish.sh --force

`publish.sh` 是把 `godogen` 运行时发布到目标游戏仓库的脚本。对 Codex，它会创建 `AGENTS.md` 和 `.agents/skills/asset-gen`；`--force` 会清空目标目录。来源：[README.md lines 50-60](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/README.md#L50-L60)、[publish.sh](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/publish.sh)。

本项目已有 `.codex/skills/` 角色技能体系、Godot 项目文件和大量资源。直接发布会引入第二套 agent 目录约定，`--force` 更会有破坏性风险。

### 不要迁移到 C# 只为使用 godogen

`godogen` 自己的 Godot guide 选择 C#/.NET，是为了让代理生成新项目时更容易通过编译门禁和构建期场景生成。本项目已经是 GDScript 代码库，且现有 `.codex/skills/godot-gdscript-specialist` 明确强调静态类型、信号、协程和 GDScript 习惯。迁移语言不是资产生成或验证流程的前置条件。

如果未来确实想评估 C#/.NET 场景生成，应该只在独立 prototype branch 做。`godogen` 的 setup 文档还要求 Godot .NET edition，并说明 Godot 4.5+ 需要 .NET 9；这会给当前 GDScript 客户端增加工具链和混合语言复杂度。来源：[setup.md lines 5-8](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/setup.md#L5-L8)、[setup.md lines 92-95](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/setup.md#L92-L95)。

### 不要把付费生成变成默认动作

`asset-gen` 明确说明生成会产生真实费用，第一次付费生成前需要用户确认。来源：[asset-gen/SKILL.md lines 90-92](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/asset-gen/SKILL.md#L90-L92)。

本项目应规定：

- 每批资产先列清单、成本估算、目标路径。
- 用户确认后再调用付费 API。
- GLB / rig / retarget 失败或超时时先 resume，不要重新提交，避免重复扣费。来源：[asset-gen/SKILL.md lines 81-88](https://github.com/htdt/godogen/blob/05cebffc8b10c5817e8a3db495b82e7b6004ab84/asset-gen/SKILL.md#L81-L88)。

## 推荐落地方案

### 阶段 1：只移植 asset-gen skill

把 `godogen/asset-gen/` 复制为本项目的一个 Codex skill，例如：

```text
.codex/skills/asset-gen/
```

需要做轻量改造：

- 把 `${ASSET_GEN_SKILL_DIR}` 替换为 `.codex/skills/asset-gen`。
- 把 `${RUNTIME_ASSET_DIR}` 的约定改为 `assets`。
- 在 skill 文档里加入本项目的资源路径规范：运行期资源进 `assets/`，生成中间件进 `tmp/asset-gen/`。
- 保留“付费前确认”和“Tripo3D resume 避免重复扣费”的规则。

### 阶段 2：建立资产清单和替换批次

新增 `docs/asset-manifest.md`，先收录已有关键资源和缺口。第一批建议只做 5-10 个可见度高的资产，例如：

- 小飞猫 reference + happy/hint 两组动作。
- 蜃影客栈主背景。
- 客栈 3-4 个经营物件。
- 麦克风按钮或星星奖励的一组 UI 动效。

### 阶段 3：接入验证

增加一个轻量验证脚本或文档命令：

- 导入检查：Godot headless import。
- 启动检查：Godot headless quit。
- 场景检查：关键场景截图，人工或视觉检查确认没有缺图、错位、比例错误。
- 导入检查清单：GLB owner chain、primitive collision、`assets/` 下无 `.gdignore`。

如果之后要做自动录像，再参考 `godogen` 的固定 FPS / 15 秒 proof video 思路，但用 GDScript 或 Godot 原生场景适配本项目。

## 一句话判断

`godogen` 对本项目的价值不是“把项目变成 godogen 项目”，而是把它的资产生产线和运行验证纪律拿过来：用 `asset-gen` 批量替换占位资源，用截图/录像证明 Godot 场景真的跑起来；保留本项目现有 GDScript 架构、目录结构和 `.codex/skills` 工作流。
