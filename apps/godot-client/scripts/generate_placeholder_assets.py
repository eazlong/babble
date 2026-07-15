#!/usr/bin/env python3
"""SpiritForest 美术资源占位符生成器

用 Pillow 绘制符合 art_assets.md §规格尺寸/配色的占位 PNG，让场景可以跑起来，
等美术师制作标准贴图后替换。

用法:
    pip install Pillow
    python3 apps/godot-client/scripts/generate_placeholder_assets.py

运行后会:
1. 在 assets/textures/  assets/sprites/  assets/audio/ 下生成 PNG/占位文件
2. 不会覆盖已存在的文件 (如需覆盖请删除旧文件)
3. 跳过已在仓库里的现有资源 (feifei_fly_01~08.png, mushroom_*.png, backgrounds/*.png 等)
"""
from pathlib import Path
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("错误: 未安装 Pillow，请执行 'pip install Pillow' 后重试")
    sys.exit(1)

# 项目根目录 = 本脚本在 apps/godot-client/scripts/，根 = 上两级
ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"

# ---------------------------------------------------------------------------
# 字体
# ---------------------------------------------------------------------------
FONT_CANDIDATES = [
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFNSMono.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "C:\\Windows\\Fonts\\msyh.ttc",
    "C:\\Windows\\Fonts\\arial.ttf",
]


def get_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


# ---------------------------------------------------------------------------
# 颜色/绘制工具
# ---------------------------------------------------------------------------
def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def draw_rounded_rect(draw: ImageDraw.ImageDraw, xy, radius, fill):
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def draw_text_centered(draw: ImageDraw.ImageDraw, size, text, font, fill=(255, 255, 255)):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (size[0] - tw) // 2 - bbox[0]
    ty = (size[1] - th) // 2 - bbox[1]
    # 阴影
    draw.text((tx + 1, ty + 1), text, fill=(0, 0, 0), font=font)
    draw.text((tx, ty), text, fill=fill, font=font)


def make_placeholder(path: Path, size: tuple[int, int], color: str, shape: str,
                     label: str, alpha: bool) -> None:
    """生成一张占位符 PNG。
    shape: 'circle' | 'rect' | 'star' | 'solid' | 'gradient_radial' | 'glow'
    """
    mode = "RGBA" if alpha else "RGB"
    bg = (0, 0, 0, 0) if alpha else (220, 220, 220)
    img = Image.new(mode, size, bg)
    draw = ImageDraw.Draw(img, "RGBA" if alpha else "RGB")
    rgb = hex_to_rgb(color)

    if shape == "solid":
        draw.rectangle([0, 0, size[0], size[1]], fill=rgb + (255,) if alpha else rgb)
    elif shape == "circle":
        m = min(size) // 8
        draw.ellipse([m, m, size[0] - m, size[1] - m], fill=rgb + (255,) if alpha else rgb)
    elif shape == "ellipse":
        m = size[0] // 10
        my = size[1] // 10
        draw.ellipse([m, my, size[0] - m, size[1] - my], fill=rgb + (255,) if alpha else rgb)
    elif shape == "rect":
        m = min(size) // 10
        draw_rounded_rect(draw, [m, m, size[0] - m, size[1] - m], radius=8,
                          fill=rgb + (255,) if alpha else rgb)
    elif shape == "gradient_radial":
        # 中心白色 → 边缘颜色（径向渐变，用于光晕/发光）
        cx, cy = size[0] // 2, size[1] // 2
        max_r = min(size) // 2
        for r in range(max_r, 0, -1):
            t = r / max_r
            cr = int(255 * t + rgb[0] * (1 - t))
            cg = int(255 * t + rgb[1] * (1 - t))
            cb = int(255 * t + rgb[2] * (1 - t))
            ca = int(255 * (1 - t)) if alpha else 255
            draw.ellipse([cx - r, cy - r, cx + r, cy + r],
                         fill=(cr, cg, cb, ca) if alpha else (cr, cg, cb))
    elif shape == "glow":
        # 中心亮，边缘全透明
        cx, cy = size[0] // 2, size[1] // 2
        max_r = min(size) // 2
        for r in range(max_r, 0, -1):
            t = r / max_r
            a = int(255 * (1 - t) * 0.8)
            draw.ellipse([cx - r, cy - r, cx + r, cy + r],
                         fill=rgb + (a,))
    elif shape == "star":
        # 五角星（简易版：用多边形）
        import math
        cx, cy = size[0] // 2, size[1] // 2
        r_out = min(size) // 2 - 4
        r_in = r_out * 0.4
        pts = []
        for i in range(10):
            angle = math.pi / 2 + i * math.pi / 5
            r = r_out if i % 2 == 0 else r_in
            pts.append((cx + r * math.cos(angle), cy - r * math.sin(angle)))
        draw.polygon(pts, fill=rgb + (255,) if alpha else rgb)
    elif shape == "tree":
        # 树干 + 圆形树冠
        trunk_w, trunk_h = size[0] // 5, size[1] // 3
        trunk_x = (size[0] - trunk_w) // 2
        trunk_y = size[1] - trunk_h
        trunk_col = hex_to_rgb("#8B6F47")
        draw.rectangle([trunk_x, trunk_y, trunk_x + trunk_w, size[1]],
                       fill=trunk_col + (255,) if alpha else trunk_col)
        crown_r = size[0] // 2 - 4
        cx = size[0] // 2
        cy = size[1] // 2
        draw.ellipse([cx - crown_r, cy - crown_r, cx + crown_r, cy + crown_r],
                     fill=rgb + (255,) if alpha else rgb)
    elif shape == "mushroom":
        # 蘑菇：下半柄 + 上半伞
        stem_w = size[0] // 3
        stem_h = size[1] // 2
        stem_x = (size[0] - stem_w) // 2
        stem_y = size[1] - stem_h
        draw.rectangle([stem_x, stem_y, stem_x + stem_w, size[1]],
                       fill=(255, 255, 255) + (255,) if alpha else (255, 255, 255))
        cap_r = size[0] // 2 - 2
        cx = size[0] // 2
        draw.ellipse([cx - cap_r, 4, cx + cap_r, 4 + cap_r * 2],
                     fill=rgb + (255,) if alpha else rgb)
    elif shape == "flower":
        # 花茎 + 花瓣（5个圆）+ 花心
        import math
        stem_col = hex_to_rgb("#4A7C29")
        stem_w = max(3, size[0] // 20)
        cx = size[0] // 2
        draw.rectangle([cx - stem_w // 2, size[1] // 2, cx + stem_w // 2, size[1] - 2],
                       fill=stem_col + (255,) if alpha else stem_col)
        # 花瓣
        petal_r = size[0] // 5
        for i in range(5):
            angle = -math.pi / 2 + i * 2 * math.pi / 5
            px = cx + int(petal_r * math.cos(angle))
            py = size[1] // 3 + int(petal_r * math.sin(angle))
            draw.ellipse([px - petal_r, py - petal_r, px + petal_r, py + petal_r],
                         fill=rgb + (255,) if alpha else rgb)
        # 花心
        center_r = petal_r // 2
        center_col = hex_to_rgb("#F4A261")
        draw.ellipse([cx - center_r, size[1] // 3 - center_r,
                      cx + center_r, size[1] // 3 + center_r],
                     fill=center_col + (255,) if alpha else center_col)
    elif shape == "feifei":
        # Feifei：金色圆 + 两片翅膀（白色半透明椭圆）
        cx, cy = size[0] // 2, size[1] // 2
        body_r = min(size) // 3
        draw.ellipse([cx - body_r, cy - body_r, cx + body_r, cy + body_r],
                     fill=rgb + (255,) if alpha else rgb)
        # 眼睛
        eye_r = body_r // 8
        draw.ellipse([cx - body_r // 3 - eye_r, cy - body_r // 4 - eye_r,
                      cx - body_r // 3 + eye_r, cy - body_r // 4 + eye_r],
                     fill=(0, 0, 0) + (255,) if alpha else (0, 0, 0))
        draw.ellipse([cx + body_r // 3 - eye_r, cy - body_r // 4 - eye_r,
                      cx + body_r // 3 + eye_r, cy - body_r // 4 + eye_r],
                     fill=(0, 0, 0) + (255,) if alpha else (0, 0, 0))
        # 翅膀
        wing_col = (255, 255, 255, 150) if alpha else (240, 240, 240)
        draw.ellipse([cx - body_r - body_r // 2, cy - body_r // 3,
                      cx - body_r // 2, cy + body_r // 3], fill=wing_col)
        draw.ellipse([cx + body_r // 2, cy - body_r // 3,
                      cx + body_r + body_r // 2, cy + body_r // 3], fill=wing_col)
    elif shape == "owl":
        # Oakley：椭圆身体 + 大眼 + 喙
        cx, cy = size[0] // 2, size[1] // 2
        body_rx, body_ry = size[0] // 2 - 4, size[1] // 2 - 4
        draw.ellipse([cx - body_rx, cy - body_ry, cx + body_rx, cy + body_ry],
                     fill=rgb + (255,) if alpha else rgb)
        # 眼睛
        eye_r = body_rx // 4
        eye_col = (255, 230, 100) + (255,) if alpha else (255, 230, 100)
        draw.ellipse([cx - body_rx // 2 - eye_r, cy - body_ry // 3 - eye_r,
                      cx - body_rx // 2 + eye_r, cy - body_ry // 3 + eye_r], fill=eye_col)
        draw.ellipse([cx + body_rx // 2 - eye_r, cy - body_ry // 3 - eye_r,
                      cx + body_rx // 2 + eye_r, cy - body_ry // 3 + eye_r], fill=eye_col)
        # 瞳孔
        pupil_r = eye_r // 2
        pupil_col = (0, 0, 0) + (255,) if alpha else (0, 0, 0)
        draw.ellipse([cx - body_rx // 2 - pupil_r, cy - body_ry // 3 - pupil_r,
                      cx - body_rx // 2 + pupil_r, cy - body_ry // 3 + pupil_r], fill=pupil_col)
        draw.ellipse([cx + body_rx // 2 - pupil_r, cy - body_ry // 3 - pupil_r,
                      cx + body_rx // 2 + pupil_r, cy - body_ry // 3 + pupil_r], fill=pupil_col)
        # 喙
        beak_col = hex_to_rgb("#E67E22")
        draw.polygon([(cx, cy - 2), (cx - 6, cy + 8), (cx + 6, cy + 8)],
                     fill=beak_col + (255,) if alpha else beak_col)
    elif shape == "player":
        # 玩家：头+身体+腿 三段
        cx = size[0] // 2
        head_r = size[0] // 5
        skin = hex_to_rgb("#F5D6B3")
        robe = hex_to_rgb("#457B9D")
        draw.ellipse([cx - head_r, 4, cx + head_r, 4 + head_r * 2],
                     fill=skin + (255,) if alpha else skin)
        draw.rectangle([cx - head_r, 4 + head_r * 2, cx + head_r, size[1] - size[1] // 5],
                       fill=robe + (255,) if alpha else robe)
        # 腿
        leg_col = hex_to_rgb("#2C2C2C")
        draw.rectangle([cx - head_r // 2, size[1] - size[1] // 5,
                        cx - 2, size[1] - 2],
                       fill=leg_col + (255,) if alpha else leg_col)
        draw.rectangle([cx + 2, size[1] - size[1] // 5,
                        cx + head_r // 2, size[1] - 2],
                       fill=leg_col + (255,) if alpha else leg_col)
    elif shape == "hands":
        # 第一人称手部：两根手指握法杖
        hand_col = hex_to_rgb("#F5D6B3")
        staff_col = hex_to_rgb("#8B6F47")
        # 法杖（斜向）
        draw.line([(size[0] // 2, size[1] - 10), (size[0] // 2 - 20, 20)],
                  fill=staff_col, width=8)
        # 顶部水晶
        crystal_col = hex_to_rgb("#FFD700")
        cx, cy = size[0] // 2 - 20, 20
        draw.ellipse([cx - 12, cy - 12, cx + 12, cy + 12], fill=crystal_col)
        # 手
        draw.ellipse([size[0] // 2 - 30, size[1] - 50, size[0] // 2 + 30, size[1] - 10],
                     fill=hand_col)
    else:
        # 默认：填充矩形
        draw.rectangle([0, 0, size[0], size[1]], fill=rgb + (255,) if alpha else rgb)

    # 中央标签
    font = get_font(max(10, min(size) // 8))
    draw_text_centered(draw, size, label, font)

    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    print(f"  生成: {path.relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# 资源清单（P0 必需，§8.1 + §8.4）
# ---------------------------------------------------------------------------
# 格式：(相对路径, 尺寸, 颜色, 形状, 是否透明)
# 形状见 make_placeholder 的 shape 分支
RESOURCES = [
    # === §2.1 环境对象（必需）===
    ("textures/objects/tree_big.png", (200, 300), "#4A7C29", "tree", True),
    ("textures/objects/stream.png", (200, 80), "#4A90D9", "rect", True),
    ("textures/objects/rock_small.png", (60, 50), "#808080", "ellipse", True),
    ("textures/objects/rock_medium.png", (100, 80), "#808080", "ellipse", True),
    ("textures/objects/bush_small.png", (120, 80), "#5A9E32", "circle", True),
    ("textures/objects/bush_large.png", (180, 120), "#5A9E32", "circle", True),

    # === §2.2 魔法花朵（必需）===
    ("textures/objects/flower_red.png", (80, 100), "#E63946", "flower", True),
    ("textures/objects/flower_blue.png", (80, 100), "#457B9D", "flower", True),
    ("textures/objects/flower_yellow.png", (80, 100), "#F4A261", "flower", True),
    ("textures/objects/flower_glow.png", (100, 120), "#FFD700", "glow", True),

    # === §3.1 Feifei 精灵（必需，已有 idle+fly，缺 happy/hint/glow）===
    ("sprites/feifei/feifei_happy_01.png", (120, 120), "#FFD700", "feifei", True),
    ("sprites/feifei/feifei_happy_02.png", (120, 120), "#FFD700", "feifei", True),
    ("sprites/feifei/feifei_happy_03.png", (120, 120), "#FFD700", "feifei", True),
    ("sprites/feifei/feifei_happy_04.png", (120, 120), "#FFD700", "feifei", True),
    ("sprites/feifei/feifei_hint_01.png", (120, 120), "#FFD700", "feifei", True),
    ("sprites/feifei/feifei_hint_02.png", (120, 120), "#FFD700", "feifei", True),
    ("sprites/feifei/feifei_glow.png", (140, 140), "#FFD700", "glow", True),

    # === §3.2 TreeSpirit NPC（第一人称核心，P0）===
    ("sprites/tree_spirit/tree_spirit_body.png", (400, 600), "#4A7C29", "tree", True),
    ("sprites/tree_spirit/tree_spirit_eye_white.png", (80, 40), "#FFFFFF", "rect", True),
    ("sprites/tree_spirit/tree_spirit_pupil.png", (20, 20), "#000000", "circle", True),

    # === §3.3 Oakley NPC（必需）===
    ("sprites/oakley/oakley_idle_01.png", (150, 180), "#8B6F47", "owl", True),
    ("sprites/oakley/oakley_idle_02.png", (150, 180), "#8B6F47", "owl", True),
    ("sprites/oakley/oakley_idle_03.png", (150, 180), "#8B6F47", "owl", True),
    ("sprites/oakley/oakley_idle_04.png", (150, 180), "#8B6F47", "owl", True),
    ("sprites/oakley/oakley_talk_01.png", (150, 180), "#8B6F47", "owl", True),
    ("sprites/oakley/oakley_talk_02.png", (150, 180), "#8B6F47", "owl", True),
    ("sprites/oakley/oakley_talk_03.png", (150, 180), "#8B6F47", "owl", True),
    ("sprites/oakley/oakley_happy_01.png", (150, 180), "#8B6F47", "owl", True),
    ("sprites/oakley/oakley_happy_02.png", (150, 180), "#8B6F47", "owl", True),

    # === §4 玩家角色 ===
    ("sprites/player/player_idle_01.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_idle_02.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_idle_03.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_idle_04.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_walk_01.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_walk_02.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_walk_03.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_walk_04.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_walk_05.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_walk_06.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_talk_01.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_talk_02.png", (80, 120), "#457B9D", "player", True),
    ("sprites/player/player_talk_03.png", (80, 120), "#457B9D", "player", True),

    # === §4.1 第一人称手部（P0）===
    ("sprites/player/player_hands_idle.png", (200, 150), "#F5D6B3", "hands", True),

    # === §5.1 粒子纹理 ===
    ("textures/particles/particle_glow.png", (32, 32), "#FFD700", "gradient_radial", True),
    ("textures/particles/particle_feifeile.png", (16, 16), "#FFFFFF", "star", True),

    # === §5.2 交互反馈特效 ===
    ("textures/effects/effect_glow_01.png", (100, 100), "#FFD700", "glow", True),
    ("textures/effects/effect_glow_02.png", (100, 100), "#FFD700", "glow", True),
    ("textures/effects/effect_glow_03.png", (100, 100), "#FFD700", "glow", True),
    ("textures/effects/effect_glow_04.png", (100, 100), "#FFD700", "glow", True),
    ("textures/effects/effect_glow_05.png", (100, 100), "#FFD700", "glow", True),
    ("textures/effects/effect_bounce_01.png", (80, 80), "#FFD700", "circle", True),
    ("textures/effects/effect_bounce_02.png", (80, 80), "#FFD700", "circle", True),
    ("textures/effects/effect_bounce_03.png", (80, 80), "#FFD700", "circle", True),
    ("textures/effects/effect_color_shift_01.png", (80, 80), "#E8A4B8", "circle", True),
    ("textures/effects/effect_color_shift_02.png", (80, 80), "#9B59B6", "circle", True),
    ("textures/effects/effect_color_shift_03.png", (80, 80), "#457B9D", "circle", True),
    ("textures/effects/effect_color_shift_04.png", (80, 80), "#457B9D", "circle", True),
    ("textures/effects/effect_stars_1.png", (120, 120), "#FFD700", "star", True),
    ("textures/effects/effect_stars_2.png", (120, 120), "#FFD700", "star", True),
    ("textures/effects/effect_stars_3.png", (120, 120), "#FFD700", "star", True),
    ("textures/effects/effect_stars_4.png", (120, 120), "#FFD700", "star", True),
    ("textures/effects/effect_stars_5.png", (120, 120), "#FFD700", "star", True),

    # === §5.3 场景过渡特效 ===
    ("textures/effects/transition_wipe.png", (1920, 1080), "#000000", "gradient_radial", True),
    ("textures/effects/transition_fade.png", (64, 64), "#FFFFFF", "gradient_radial", True),

    # === §6.1 对话气泡 ===
    ("textures/ui/bubble_npc.png", (400, 200), "#FFFFFF", "rect", True),
    ("textures/ui/bubble_feifei.png", (350, 180), "#FFF9E6", "rect", True),
    ("textures/ui/bubble_tail.png", (40, 60), "#FFFFFF", "solid", True),

    # === §6.2 徽章与奖励 ===
    ("textures/ui/badge_forest.png", (150, 150), "#4A7C29", "circle", True),
    ("textures/ui/badge_glow.png", (180, 180), "#FFD700", "glow", True),
    ("textures/ui/badge_unlock_effect_01.png", (300, 300), "#FFD700", "glow", True),
    ("textures/ui/badge_unlock_effect_02.png", (300, 300), "#FFD700", "glow", True),
    ("textures/ui/badge_unlock_effect_03.png", (300, 300), "#FFD700", "glow", True),
    ("textures/ui/badge_unlock_effect_04.png", (300, 300), "#FFD700", "glow", True),
    ("textures/ui/badge_unlock_effect_05.png", (300, 300), "#FFD700", "glow", True),
    ("textures/ui/badge_unlock_effect_06.png", (300, 300), "#FFD700", "glow", True),

    # === §6.4 第一人称专属 UI（P0）===
    ("textures/ui/fp/ui_starbar_bg.png", (400, 40), "#1A1A26", "rect", True),
    ("textures/ui/fp/ui_starbar_fill.png", (380, 30), "#FFD700", "rect", True),
    ("textures/ui/fp/ui_mic_button_idle.png", (80, 80), "#20C997", "circle", True),
    ("textures/ui/fp/ui_mic_button_recording.png", (80, 80), "#E63946", "circle", True),
    ("textures/ui/fp/ui_feifei_bubble_fp.png", (200, 100), "#FFF9E6", "rect", True),
]


def generate_all() -> None:
    print(f"项目根目录: {ROOT}")
    print(f"资源清单共 {len(RESOURCES)} 个 PNG\n")

    skipped = 0
    created = 0
    for rel, size, color, shape, alpha in RESOURCES:
        p = ASSETS / rel
        if p.exists():
            skipped += 1
            continue
        label = Path(rel).stem
        make_placeholder(p, size, color, shape, label, alpha)
        created += 1

    print(f"\n完成! 新生成 {created} 个, 已存在跳过 {skipped} 个")


def create_audio_placeholders() -> None:
    """音频无法用 Pillow 生成，创建说明文件提示需要补充。"""
    audio_dir = ASSETS / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)

    needed = [
        ("bgm/forest_ambient.ogg", "60-120s 循环森林环境 BGM"),
        ("sfx/bird_chirp_01.ogg", "清脆短鸣 2 声"),
        ("sfx/bird_chirp_02.ogg", "悠长鸣叫 1 声"),
        ("sfx/bird_chirp_03.ogg", "急促连续鸣叫 4 声"),
        ("sfx/magic_feifeile.ogg", "清脆铃铛 + 星光"),
        ("sfx/badge_unlock.ogg", "5-8s 解锁音效"),
    ]
    readme = audio_dir / "AUDIO_PLACEHOLDERS.txt"
    with open(readme, "w", encoding="utf-8") as f:
        f.write("音频占位说明（需后续补充真实音频文件）\n")
        f.write("=" * 50 + "\n\n")
        f.write("本目录需要的音频文件（按 design/art/spirit_forest_art_assets.md §7）:\n\n")
        for path, desc in needed:
            f.write(f"  {path:35s} - {desc}\n")
        f.write("\n建议使用 OGG Vorbis 格式，BGM 128kbps，SFX 96kbps\n")
    print(f"  生成: {readme.relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# SpriteFrames .tres 生成
# ---------------------------------------------------------------------------
# 每个动画：(输出路径, 帧列表(相对路径), fps, 是否循环, 动画名)
SPRITE_ANIMS = [
    ("sprites/feifei/feifei_happy_frames.tres",
     [f"sprites/feifei/feifei_happy_0{i}.png" for i in range(1, 5)],
     4, False, "default"),
    ("sprites/feifei/feifei_hint_frames.tres",
     ["sprites/feifei/feifei_hint_01.png", "sprites/feifei/feifei_hint_02.png"],
     2, True, "default"),
    ("sprites/oakley/oakley_idle_frames.tres",
     [f"sprites/oakley/oakley_idle_0{i}.png" for i in range(1, 5)],
     4, True, "default"),
    ("sprites/oakley/oakley_talk_frames.tres",
     [f"sprites/oakley/oakley_talk_0{i}.png" for i in range(1, 4)],
     6, True, "default"),
    ("sprites/oakley/oakley_happy_frames.tres",
     ["sprites/oakley/oakley_happy_01.png", "sprites/oakley/oakley_happy_02.png"],
     2, False, "default"),
    ("sprites/player/player_idle_frames.tres",
     [f"sprites/player/player_idle_0{i}.png" for i in range(1, 5)],
     4, True, "default"),
    ("sprites/player/player_walk_frames.tres",
     [f"sprites/player/player_walk_0{i}.png" for i in range(1, 7)],
     6, True, "default"),
    ("sprites/player/player_talk_frames.tres",
     [f"sprites/player/player_talk_0{i}.png" for i in range(1, 4)],
     6, True, "default"),
    ("textures/effects/effect_glow_frames.tres",
     [f"textures/effects/effect_glow_0{i}.png" for i in range(1, 6)],
     10, False, "default"),
    ("textures/effects/effect_bounce_frames.tres",
     [f"textures/effects/effect_bounce_0{i}.png" for i in range(1, 4)],
     15, False, "default"),
    ("textures/effects/effect_color_shift_frames.tres",
     [f"textures/effects/effect_color_shift_0{i}.png" for i in range(1, 5)],
     8, False, "default"),
    ("textures/ui/fp/ui_starbar_frames.tres",
     ["textures/ui/fp/ui_starbar_bg.png", "textures/ui/fp/ui_starbar_fill.png"],
     2, True, "default"),
    ("textures/ui/badge_unlock_effect_frames.tres",
     [f"textures/ui/badge_unlock_effect_0{i}.png" for i in range(1, 7)],
     8, False, "default"),
]


def generate_spriteframes() -> None:
    """批量生成 SpriteFrames .tres 文件（不含 uid，Godot 导入时会自动分配）。"""
    print(f"\n生成 {len(SPRITE_ANIMS)} 个 SpriteFrames .tres\n")
    for out_rel, frames, fps, loop, anim_name in SPRITE_ANIMS:
        out_path = ASSETS / out_rel
        # ext_resource 段落
        ext_lines = []
        frame_entries = []
        for i, frame_rel in enumerate(frames, 1):
            res_id = f"{i}"
            ext_lines.append(
                f'[ext_resource type="Texture2D" path="res://assets/{frame_rel}" id="{res_id}"]'
            )
            frame_entries.append(
                f'{{\n"duration": 1.0,\n"texture": ExtResource("{res_id}")\n}}'
            )
        frames_str = ", ".join(frame_entries)
        loop_str = "true" if loop else "false"
        load_steps = len(frames) + 1  # ext_resources + resource
        content = (
            f"[gd_resource type=\"SpriteFrames\" load_steps={load_steps} format=3]\n\n"
            + "\n".join(ext_lines)
            + "\n\n[resource]\n"
            + f"animations = [{{\n\"frames\": [{frames_str}],\n"
            + f"\"loop\": {loop_str},\n"
            + f"\"name\": &\"{anim_name}\",\n"
            + f"\"speed\": {float(fps)}\n}}]\n"
        )
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(content, encoding="utf-8")
        print(f"  生成: {out_path.relative_to(ROOT)}")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    print("=" * 60)
    print("SpiritForest 占位资源生成器")
    print("=" * 60)
    generate_all()
    generate_spriteframes()
    create_audio_placeholders()
    print("\n下一步:")
    print("  1. 在 Godot 编辑器中重新导入资源 (FileSystem → 右键 → Reimport)")
    print("  2. 重命名 tree-big.png → tree_big.png 并更新 .tscn 引用")
    print("  3. 生成的 SpriteFrames .tres 需要手动关联帧图（见 scripts/PLACEHOLDER_README.md）")
