# SpiritForest 占位资源使用说明

由于 Bash/Agent 工具当前被安全分类器拒绝，我无法直接运行脚本。请手动执行以下步骤。

## 1. 安装依赖

```bash
cd apps/godot-client
pip install Pillow
```

## 2. 运行生成脚本

```bash
python3 scripts/generate_placeholder_assets.py
```

脚本会生成：
- **~75 个占位 PNG**（带配色+标签的几何图形，按 art_assets.md 规格尺寸）
- **13 个 SpriteFrames .tres**（动画配置，引用生成的 PNG）
- **1 个音频占位说明**（audio/AUDIO_PLACEHOLDERS.txt）

## 3. 重命名 tree-big.png

```bash
cd apps/godot-client/assets/textures/objects
mv tree-big.png tree_big.png
mv tree-big.png.import tree_big.png.import
```

然后更新 .tscn 引用：

```bash
# SpiritForest.tscn
sed -i '' 's|tree-big.png|tree_big.png|g' assets/scenes/SpiritForest.tscn
# SpiritForestFP.tscn
sed -i '' 's|tree-big.png|tree_big.png|g' assets/scenes/SpiritForestFP.tscn
```

或者在 Godot 编辑器中手动重新链接资源。

## 4. 重新导入资源

在 Godot 编辑器中：
- FileSystem → 右键项目根 → **Reimport All**
- 或按 F5 运行场景时自动导入

## 5. 后续替换真实美术

占位 PNG 使用几何图形（圆/椭圆/五角星）+ 中央标签。美术师完成标准贴图后，直接替换同路径同尺寸的文件即可，SpriteFrames 引用会自动生效。

## 生成的文件清单

### textures/objects/（10个新增）
tree_big.png, stream.png, rock_small.png, rock_medium.png, bush_small.png, bush_large.png, flower_red.png, flower_blue.png, flower_yellow.png, flower_glow.png

### sprites/feifei/（7个新增）
feifei_happy_01~04.png, feifei_hint_01~02.png, feifei_glow.png

### sprites/tree_spirit/（3个新增）
tree_spirit_body.png (400x600), tree_spirit_eye_white.png (80x40), tree_spirit_pupil.png (20x20)

### sprites/oakley/（9个新增）
oakley_idle_01~04.png, oakley_talk_01~03.png, oakley_happy_01~02.png

### sprites/player/（14个新增）
player_idle_01~04.png, player_walk_01~06.png, player_talk_01~03.png, player_hands_idle.png

### textures/particles/（2个新增）
particle_glow.png, particle_feifeile.png

### textures/effects/（18个新增 + 3个 .tres）
effect_glow_01~05.png + effect_glow_frames.tres
effect_bounce_01~03.png + effect_bounce_frames.tres
effect_color_shift_01~04.png + effect_color_shift_frames.tres
effect_stars_1~5.png
transition_wipe.png, transition_fade.png

### textures/ui/（12个新增 + 1个 .tres）
bubble_npc.png, bubble_feifei.png, bubble_tail.png
badge_forest.png, badge_glow.png
badge_unlock_effect_01~06.png + badge_unlock_effect_frames.tres

### textures/ui/fp/（5个新增 + 1个 .tres）
ui_starbar_bg.png, ui_starbar_fill.png, ui_starbar_frames.tres
ui_mic_button_idle.png, ui_mic_button_recording.png
ui_feifei_bubble_fp.png

### sprites/ 动画 .tres（8个新增）
feifei_happy_frames.tres, feifei_hint_frames.tres
oakley_idle_frames.tres, oakley_talk_frames.tres, oakley_happy_frames.tres
player_idle_frames.tres, player_walk_frames.tres, player_talk_frames.tres

### audio/（说明文件，音频需手动补充）
AUDIO_PLACEHOLDERS.txt

## SpriteFrames .tres 说明

生成的 .tres 不含 `uid` 字段（因为 PNG 尚未被 Godot 导入）。首次打开 Godot 时会自动分配 uid 并更新文件。如果 Godot 报错找不到资源，执行 Reimport All。

每个 .tres 的动画参数按 art_assets.md 规格：
- feifei_happy: 4 FPS, 不循环
- feifei_hint: 2 FPS, 循环
- oakley_idle: 4 FPS, 循环
- oakley_talk: 6 FPS, 循环
- oakley_happy: 2 FPS, 不循环
- player_idle: 4 FPS, 循环
- player_walk: 6 FPS, 循环
- player_talk: 6 FPS, 循环
- effect_glow: 10 FPS, 不循环
- effect_bounce: 15 FPS, 不循环
- effect_color_shift: 8 FPS, 不循环
- badge_unlock_effect: 8 FPS, 不循环

## 缺失的真实音频（需手动补充）

- `audio/bgm/forest_ambient.ogg` - 60-120s 森林 BGM
- `audio/sfx/bird_chirp_01.ogg` - 清脆短鸣
- `audio/sfx/bird_chirp_02.ogg` - 悠长鸣叫
- `audio/sfx/bird_chirp_03.ogg` - 急促连续鸣叫
- `audio/sfx/magic_feifeile.ogg` - 魔法闪烁音效
- `audio/sfx/badge_unlock.ogg` - 徽章解锁音效
