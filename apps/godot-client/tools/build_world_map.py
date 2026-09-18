#!/usr/bin/env python3
"""把生成的世界地图合成成游戏用的「序章介绍地图」。

产物：assets/textures/backgrounds/beginning_mist_continents.png（1320x440）

为什么是 1320x440：
  BeginningFPController 里 DistantContinents 是 **世界空间** Node2D，位于 (960,350)，
  子节点 Sprite2D centered=true、无缩放 —— 所以贴图按 1:1 以 (960,350) 居中显示。
  相机在 (960,540)、视口 1920x1080 => 贴图 1320x440 会占屏幕 y 130~570：
  上不压顶部任务条（y 66~106）、下不压麦克风，左右留出房间。改贴图尺寸无需改代码。

六道光为什么要自己贴，而不是让模型画：
  台词是「你看。六道光，就是六块大陆。」——精确数量（6）属于符号化任务，
  图像模型给不准（本轮实测同一 prompt 只给 4~5 个光点、且落在山上而非大陆上）。
  改用项目里已存在的六件神器图标（artifact_*.png，256x256 透明底）作为道标，
  既凑准 6 个，又顺势把「每块大陆对应一件神器」的设定画进去。

用法：
  .venv/bin/python tools/build_world_map.py --src <生成图.png> [--out ...]
"""

from __future__ import annotations

import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# 六道光在 1320x440 贴图内的坐标。
#
# 为什么是"以中央小岛为圆心的环"：模型不会数准"六块大陆/六道光"（精确数量属于
# 符号化任务），而底图上大陆又被雾盖住、无法可靠地自动找陆地（实测"暖色=陆地"
# 判据同时命中雾与海）。改成有意设计的构图：六道光均匀环绕中央无雾小岛 ——
# 既凑准 6 个、又正好对上台词「你看。六道光，就是六块大陆」（光本就是从雾里透出来的）。
# 小岛中心 (660,210) 是用视觉工具读格网测出来的（横向 50%、y≈210，即横幅正中）。
LIGHTS: list[tuple[str, int, int]] = [
    ("artifact_donghuang_bell.png", 300, 210),  # 第1学期 长安西市 → 东皇钟
    ("artifact_compass.png", 476, 316),         # 第2学期 苗疆竹海 → 问路司南
    ("artifact_ruyi.png", 846, 314),            # 第3学期 星沙绿洲 → 通晓玉如意
    ("artifact_mirror.png", 1022, 208),         # 第4学期 机关偃师城 → 辩真明镜
    ("artifact_horn.png", 842, 106),            # 第5学期 龙门漕运港 → 岁月号角
    ("artifact_hetu.png", 478, 104),            # 第6学期 昆仑神宫 → 万象河图
]

BAND_H = 440
BAND_W = 1320
ICON = 96          # 图标显示边长（再小就认不出神器）
GLOW_R = 62        # 图标下的暖金辉光半径
FEATHER = 96       # 边缘柔化宽度（px）


def crop_band(src: Image.Image) -> Image.Image:
    """从生成图里取居中的 3:1 横幅带。

    提示词已要求「主体内容在画面中间的横带、上下留空雾」，所以居中裁切即得。
    """
    im = src.convert("RGB")
    y0 = (im.height - BAND_H) // 2
    return im.crop((0, y0, im.width, y0 + BAND_H)).resize((BAND_W, BAND_H), Image.LANCZOS)


def warm_grade(im: Image.Image, amount: float = 0.16) -> Image.Image:
    """轻微加暖，贴近房间墙色（墙色 R-B≈70，本图天生 R-B≈67，只做微调）。"""
    a = np.array(im).astype(np.float32)
    lum = a.mean(axis=2, keepdims=True)
    warm = np.concatenate([lum * 1.05, lum * 0.98, lum * 0.86], axis=2)
    return Image.fromarray(np.clip(a * (1 - amount) + warm * amount, 0, 255).astype(np.uint8))


def add_light(base: Image.Image, icon_path: str, cx: int, cy: int) -> None:
    """在 (cx,cy) 处叠一道「光」：暗青底衬 + 暖金辉光 + 光环 + 神器图标。

    为什么要暗色底衬：图标本身是暖色调手绘，直接压在暖色陆地/暖米色雾上几乎看不见
    （实测"万象河图"那块浅米色石板完全消失，视觉只数出 5 个光点）。先铺一层暗青
    柔边圆盘把背景压下去，图标才立得住，读作"雾里透出的一点光"。
    """
    yy, xx = np.mgrid[0:BAND_H, 0:BAND_W]
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)

    # 1) 暗青底衬（越靠中心越暗，边缘柔化）—— 提供对比度
    dark = Image.new("L", (BAND_W, BAND_H), 0)
    ImageDraw.Draw(dark).ellipse(
        [cx - GLOW_R * 1.45, cy - GLOW_R * 1.45, cx + GLOW_R * 1.45, cy + GLOW_R * 1.45], fill=104
    )
    dark = dark.filter(ImageFilter.GaussianBlur(GLOW_R * 0.55))
    base.paste(Image.new("RGB", (BAND_W, BAND_H), (34, 52, 62)), (0, 0), dark)

    # 2) 暖金辉光（加性）
    falloff = np.clip(1.0 - dist / GLOW_R, 0.0, 1.0) ** 2.0
    arr = np.array(base).astype(np.float32)
    arr += falloff[:, :, None] * np.array([255.0, 216.0, 146.0])[None, None, :] * 0.55
    base.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)), (0, 0))

    # 3) 光环（一道细的暖金光圈，把光点框出来）
    ring = Image.new("RGBA", (BAND_W, BAND_H), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse(
        [cx - GLOW_R * 0.98, cy - GLOW_R * 0.98, cx + GLOW_R * 0.98, cy + GLOW_R * 0.98],
        outline=(255, 226, 168, 190), width=2,
    )
    base.paste(Image.alpha_composite(base.convert("RGBA"), ring.filter(ImageFilter.GaussianBlur(1.1))).convert("RGB"), (0, 0))

    # 4) 神器图标本体（透明底等比缩放居中 + 轻微外发光帮助分离）
    icon = Image.open(icon_path).convert("RGBA")
    bbox = icon.split()[3].getbbox()
    if bbox:
        icon = icon.crop(bbox)
    sc = ICON / max(icon.width, icon.height)
    icon = icon.resize((max(1, round(icon.width * sc)), max(1, round(icon.height * sc))), Image.LANCZOS)
    pad = 14
    halo = Image.new("L", (icon.width + pad * 2, icon.height + pad * 2), 0)
    halo.paste(icon.split()[3], (pad, pad))
    halo = halo.filter(ImageFilter.GaussianBlur(6))
    layer = Image.new("RGBA", halo.size, (255, 232, 186, 255))
    layer.putalpha(halo.point(lambda v: int(v * 0.85)))
    x0, y0 = cx - icon.width // 2 - pad, cy - icon.height // 2 - pad
    base.paste(layer, (x0, y0), layer)
    base.paste(icon, (x0 + pad, y0 + pad), icon)


def edge_fade(im: Image.Image, feather: int = FEATHER) -> Image.Image:
    """四周 alpha 渐隐 —— 这是**关键**：贴图在世界空间、直接盖在房间上，
    硬边会变成一块方形贴纸；渐隐后读作「浮在空中的魔法投影」。

    只用"到边距离"做羽化还不够（实测视觉仍读成"贴在墙上的一块矩形画布，
    底边还是平直的"），所以再叠一层**椭圆径向衰减**，让整块地图作为一个软边
    椭圆团化在房间里；同时整体略降不透明度（0.95），让墙面透出来一点。
    """
    w, h = im.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.minimum.reduce([xx, yy, (w - 1) - xx, (h - 1) - yy])
    edge = np.clip(d / feather, 0.0, 1.0) ** 1.25
    rn = np.sqrt(((xx - (w - 1) / 2) / ((w - 1) / 2)) ** 2 + ((yy - (h - 1) / 2) / ((h - 1) / 2)) ** 2)
    radial = np.clip((1.06 - rn) / 0.34, 0.0, 1.0) ** 1.15
    out = im.convert("RGBA")
    a0 = np.array(out)[:, :, 3].astype(np.float32) / 255.0
    out.putalpha(Image.fromarray((np.clip(a0 * edge * radial * 0.95, 0, 1) * 255).astype(np.uint8)))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="生成的地图原图")
    ap.add_argument("--artifacts-dir", default="assets/textures/objects/artifacts")
    ap.add_argument("--out", default="assets/textures/backgrounds/beginning_mist_continents.png")
    args = ap.parse_args()

    band = warm_grade(crop_band(Image.open(args.src)))
    for name, cx, cy in LIGHTS:
        p = os.path.join(args.artifacts_dir, name)
        if not os.path.exists(p):
            print(f"  !! 缺图标 {p}")
            continue
        add_light(band, p, cx, cy)
    out = edge_fade(band)
    out.save(args.out)

    a = np.array(out)
    opaque = float((a[:, :, 3] > 200).mean())
    print(f"saved {args.out}  size={out.size}  不透明占比={opaque*100:.1f}%  四边alpha="
          f"{a[:, 0, 3].max()}/{a[:, -1, 3].max()}/{a[0, :, 3].max()}/{a[-1, :, 3].max()}")
    placed = [f"{name.split('_')[1]}@({x},{y})" for name, x, y in LIGHTS]
    print(f"  六道光已放在：{placed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
