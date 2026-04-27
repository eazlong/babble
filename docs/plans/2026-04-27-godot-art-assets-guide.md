# Godot 轨道美术资源指南

## 一、Phase 2 最小资源需求

### 1. 精灵教练 Spark

**来源**: 可复用 CocosCreator 轨道现有资源

| 资源类型 | 文件路径 | 数量/规格 | 用途 |
|---------|---------|----------|------|
| 飞入动画帧 | `textures/characters/sprite_coach/flying/*.png` | 20帧 480x270 | CoachOverlay 飞入动画 |
| 静态精灵 | `textures/characters/sprite_coach/56_480x270.jpg` | 1张 | 默认站立状态 |

**Godot 添加步骤**:
1. 复制文件到 `apps/godot-client/assets/resources/sprites/spark/`
2. 在 Godot 编辑器中导入
3. 创建 AnimatedSprite2D 资源：
   - 新建 SpriteFrames 资源
   - 添加动画 "idle" (静态帧)
   - 添加动画 "fly" (飞入动画 20帧)
   - 添加动画 "happy"、"neutral"、"greeting" (复用帧或新建)

---

### 2. 背景图片

**Phase 2 需要的背景**:

| 场景 | 文件名 | 尺寸 | 备注 |
|------|--------|------|------|
| MainMenu | `bg_mainmenu.png` | 1280x720 | 主菜单背景（魔法森林入口） |
| SpiritForest | `bg_spiritforest.png` | 1280x720 | 精灵森林场景背景 |

**临时方案**: 可使用纯色渐变或免费素材替代
- 推荐资源网站:
  - [itch.io](https://itch.io/game-assets/free/tag-background)
  - [OpenGameArt](https://opengameart.org/art-search?keys=forest)

---

### 3. 玩家角色

**需要**: 2 个动画状态

| 动画 | 文件名 | 尺寸 | 备注 |
|------|--------|------|------|
| idle | `player_idle.png` | 64x64 | 站立状态 |
| walk | `player_walk_*.png` | 64x64 x 4-8帧 | 行走动画 |

**临时方案**: 使用简单的像素方块或免费素材

---

### 4. 音效

**Phase 2 最小需求**:

| 类型 | 文件名 | 用途 |
|------|--------|------|
| BGM | `bgm_mainmenu.ogg` | 主菜单背景音乐 |
| BGM | `bgm_spiritforest.ogg` | 精灵森林场景音乐 |
| SFX | `sfx_button_click.ogg` | 按钮点击音效 |
| SFX | `sfx_voice_start.ogg` | 开始语音监听提示音 |

**临时方案**: 
- BGM 可使用静音或免费素材
- SFX 可暂时省略，功能不受影响

---

### 5. 字体

**需要**: 1 个支持中英文的字体

| 文件名 | 用途 |
|--------|------|
| `font_main.ttf` | UI 文字显示（标题、对话、按钮） |

**推荐免费字体**:
- [思源黑体](https://github.com/adobe-fonts/source-han-sans) (Noto Sans CJK)
- [Google Fonts](https://fonts.google.com/) - 选择支持中文的字体

---

## 二、资源添加步骤

### Step 1: 创建资源目录结构

```bash
mkdir -p apps/godot-client/assets/resources/sprites/{spark,player,backgrounds}
mkdir -p apps/godot-client/assets/resources/audio/{bgm,sfx}
mkdir -p apps/godot-client/assets/resources/fonts
```

### Step 2: 复制现有资源（可选）

从 CocosCreator 复制精灵教练资源：
```bash
cp apps/game-creator/assets/resources/textures/characters/sprite_coach/flying/*.png \
   apps/godot-client/assets/resources/sprites/spark/
cp apps/game-creator/assets/resources/textures/characters/sprite_coach/56_480x270.jpg \
   apps/godot-client/assets/resources/sprites/spark/spark_idle.jpg
```

### Step 3: 在 Godot 编辑器中导入

1. 打开 Godot 4.3
2. 打开项目 `apps/godot-client/project.godot`
3. 资源会自动导入到 `.godot/imported/` 目录
4. 检查 FileSystem 面板确认导入成功

### Step 4: 创建 SpriteFrames 动画资源

**Spark 精灵教练动画**:
1. 右键 `resources/sprites/spark/` → New Resource → SpriteFrames
2. 命名为 `spark_frames.tres`
3. 双击打开，添加动画:
   - "idle": 添加 spark_idle.jpg
   - "fly": 添加所有 flying/*.png 帧
   - "happy": 复用 fly 或添加新帧
   - "neutral": 复用 idle
4. 设置动画速度 (FPS): fly = 10, idle = 1

**玩家角色动画**:
1. 创建 `player_frames.tres`
2. 添加动画:
   - "idle": player_idle.png
   - "walk": player_walk_*.png 帧

### Step 5: 更新场景引用

**MainMenu.tscn**:
- CoachSprite → SpriteFrames: 加载 `spark_frames.tres`

**SpiritForest.tscn**:
- Player/Sprite → SpriteFrames: 加载 `player_frames.tres`
- SparkNPC/Sprite → SpriteFrames: 加载 `spark_frames.tres`
- Background → Texture: 加载 `bg_spiritforest.png`

---

## 三、资源格式建议

| 类型 | 推荐格式 | Godot 支持 |
|------|---------|-----------|
| 图片 | PNG (透明) / JPG (不透明) | ✅ |
| 音频 BGM | OGG Vorbis (流式) | ✅ 最佳 |
| 音频 SFX | WAV (短音效) | ✅ |
| 字体 | TTF / OTF | ✅ |

---

## 四、免费资源推荐

### 美术资源网站

| 网站 | 类型 | 许可 |
|------|------|------|
| [itch.io](https://itch.io/game-assets/free) | 2D 角色/背景/音效 | 多种免费许可 |
| [OpenGameArt](https://opengameart.org/) | 全面素材库 | CC0/CC-BY |
| [Kenney.nl](https://kenney.nl/assets) | 游戏素材包 | CC0 |
| [Game-icons.net](https://game-icons.net/) | 游戏图标 | CC-BY |

### 音效资源

| 网站 | 类型 |
|------|------|
| [Freesound](https://freesound.org/) | 音效素材 |
| [Incompetech](https://incompetech.com/music/) | 背景音乐 |
| [Bensound](https://www.bensound.com/) | 免费音乐 |

---

## 五、临时占位方案

如需快速测试功能，可使用以下临时方案：

### 纯色占位图

```bash
# 创建简单占位背景 (使用 ImageMagick)
convert -size 1280x720 xc:"#2E7D32" apps/godot-client/assets/resources/sprites/backgrounds/bg_spiritforest.png
convert -size 1280x720 xc:"#1565C0" apps/godot-client/assets/resources/sprites/backgrounds/bg_mainmenu.png

# 创建简单角色占位
convert -size 64x64 xc:"#FF5722" apps/godot-client/assets/resources/sprites/player/player_idle.png
convert -size 64x64 xc:"#FF5722" apps/godot-client/assets/resources/sprites/player/player_walk_1.png
```

### 无音频测试

代码已支持无音频运行：
- AudioManager 检查 stream 是否存在
- DialogueBox 可正常显示文字
- 语音功能需要后端 TTS，无需本地音频

---

## 六、资源清单总结

### Phase 2 必需资源

| 类别 | 数量 | 优先级 |
|------|------|--------|
| 精灵教练 SpriteFrames | 1 组 | 🔴 高 |
| 背景图片 | 2 张 | 🟡 中 |
| 玩家角色 SpriteFrames | 1 组 | 🟡 中 |
| 字体 | 1 个 | 🟢 低 |
| 音效 | 可选 | 🟢 低 |

### 可复用资源

- `sprite_coach/flying/*.png` (20帧) - 直接复用
- `sprite_coach/56_480x270.jpg` - 直接复用

### 需新建资源

- MainMenu 背景
- SpiritForest 背景
- 玩家角色动画
- 字体文件

---

**下一步**: 
1. 创建目录结构
2. 复制现有精灵教练资源
3. 在 Godot 编辑器中创建 SpriteFrames
4. 更新场景文件引用