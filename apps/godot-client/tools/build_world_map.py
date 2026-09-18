#!/usr/bin/env python3
"""把生成的世界地图合成成游戏用的「序章介绍地图」。

产物：assets/textures/backgrounds/beginning_mist_continents.png（1320x440）
      灰黑背景板 + 内嵌地图 + 六道纯光点

为什么是 1320x440：
  BeginningFPController 里 DistantContinents 是 **世界空间** Node2D，位于 (960,350)，
  子节点 Sprite2D centered=true、无缩放 —— 贴图按 1:1 以 (960,350) 居中显示。
  相机在 (960,540)、视口 1920x1080 => 贴图占屏幕 y 130~570：
  上不压顶部任务条（y 66~106）、下不压麦克风。改贴图尺寸/内容**无需改代码**。

为什么要有灰黑背景板（用户反馈：地图不够明显）：
  地图本身是暖米色绢本，直接叠在暖木墙上对比不足。所以在贴图内先铺一层灰黑板
  （留 INSET 内边距），地图缩进板内、四周柔化融进板面，整块板再做成软边 ——
  视觉上就是「房间里的一个投影面板」，地图被深色板衬出来。

六道光为什么由代码画、且用纯光点：
  （1）精确数量（6）属符号化任务：图像模型同一 prompt 只给 4~5 个光点；
  （2）用户要求「换成光点」—— 纯光点是几何图形，画上去比生成干净可控。
  六点以中央小岛为圆心均匀环绕，对上台词「你看。六道光，就是六块大陆」。

用法：
  .venv/bin/python tools/build_world_map.py --src <生成图.png> [--out ...]
"""

from __future__ import annotations

import argparse

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CANVAS_W, CANVAS_H = 1320, 440   # 贴图尺寸（与代码里的世界坐标放置绑定，勿随意改）
INSET = 44                       # 地图相对灰黑板的留白（要够宽：板外缘会再被衰减 26px）
PANEL_RADIUS = 22                # 灰黑板圆角
PANEL_RGB = (34, 36, 41)         # 灰黑
PANEL_ALPHA = 246                # 板面不透明度（留一点通透感，不至于像纯黑贴片）
EDGE_FEATHER = 26                # 整块板外缘的柔化（必须收到 alpha=0，否则贴图边界会留一圈硬切）

# 六道光点：以中央小岛为圆心的环。坐标写在「原图带 1320x440」坐标系里，
# 合成时按 INSET 映射进板内（小岛中心实测 ≈(660,211)，即带宽/带高正中）。
LIGHTS: list[tuple[int, int]] = [
    (300, 210),   # 第1学期 长安西市 → 东皇钟
    (476, 316),   # 第2学期 苗疆竹海 → 问路司南
    (846, 314),   # 第3学期 星沙绿洲 → 通晓玉如意
    (1022, 208),  # 第4学期 机关偃师城 → 辨真明镜
    (842, 106),   # 第5学期 龙门漕运港 → 岁月号角
    (478, 104),   # 第6学期 昆仑神宫 → 万象河图
]


def crop_band(src: Image.Image, out_w: int, out_h: int) -> Image.Image:
    """从生成图居中取一条横带，缩到目标尺寸。

    提示词要求「主体内容在画面中间的横带、上下留空」，所以居中裁切即得。
    """
    im = src.convert("RGB")
    band_h_src = int(im.width * out_h / out_w)
    y0 = max(0, (im.height - band_h_src) // 2)
    return im.crop((0, y0, im.width, min(im.height, y0 + band_h_src))).resize((out_w, out_h), Image.LANCZOS)


def warm_grade(im: Image.Image, amount: float = 0.16) -> Image.Image:
    """轻微加暖，贴近房间墙色（墙色 R-B≈70，本图天生 R-B≈67，只做微调）。"""
    a = np.array(im).astype(np.float32)
    lum = a.mean(axis=2, keepdims=True)
    warm = np.concatenate([lum * 1.05, lum * 0.98, lum * 0.86], axis=2)
    return Image.fromarray(np.clip(a * (1 - amount) + warm * amount, 0, 255).astype(np.uint8))


def add_light_dot(base: Image.Image, cx: int, cy: int) -> None:
    """一道光点：暗衬 + 双层暖金辉光 + 光环 + 十字星芒 + 白亮核。

    暗衬的作用（关键）：光点大多落在浅米色雾/白云上，亮核在浅底上会"白吃白"、
    被读成云的高光或脏点。用"光把周围压暗"的反向对比才托得住 —— 实测暗衬从
    112/模糊23 提到 150/模糊15（更实、更收拢）后，压在云上的点才明确读作"光"。
    """
    w, h = base.size
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)

    dark = Image.new("L", (w, h), 0)
    ImageDraw.Draw(dark).ellipse([cx - 62, cy - 62, cx + 62, cy + 62], fill=150)
    base.paste(Image.new("RGB", (w, h), (28, 42, 52)), (0, 0), dark.filter(ImageFilter.GaussianBlur(15)))

    arr = np.array(base).astype(np.float32)
    outer = np.clip(1.0 - dist / 68.0, 0.0, 1.0) ** 2.1
    inner = np.clip(1.0 - dist / 22.0, 0.0, 1.0) ** 1.5
    arr += outer[:, :, None] * np.array([255.0, 206.0, 130.0])[None, None, :] * 0.40
    arr += inner[:, :, None] * np.array([255.0, 238.0, 192.0])[None, None, :] * 0.70
    base.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)), (0, 0))

    ov = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    d.ellipse([cx - 35, cy - 35, cx + 35, cy + 35], outline=(255, 230, 178, 170), width=2)
    for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        d.line([cx + dx * 10, cy + dy * 10, cx + dx * 31, cy + dy * 31], fill=(255, 224, 164, 150), width=2)
    ov = ov.filter(ImageFilter.GaussianBlur(1.0))
    d = ImageDraw.Draw(ov)
    d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=(255, 246, 220, 240))
    d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(255, 255, 255, 255))
    base.paste(Image.alpha_composite(base.convert("RGBA"), ov).convert("RGB"), (0, 0))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="生成的地图原图")
    ap.add_argument("--out", default="assets/textures/backgrounds/beginning_mist_continents.png")
    args = ap.parse_args()

    inner_w, inner_h = CANVAS_W - INSET * 2, CANVAS_H - INSET * 2
    band = warm_grade(crop_band(Image.open(args.src), inner_w, inner_h))
    sx, sy = inner_w / CANVAS_W, inner_h / CANVAS_H
    for lx, ly in LIGHTS:
        add_light_dot(band, int(lx * sx), int(ly * sy))

    # 地图四周柔化，融进板面（否则板内会出现一圈硬边）
    a = np.array(band).astype(np.float32)
    yy, xx = np.mgrid[0:inner_h, 0:inner_w].astype(np.float32)
    d = np.minimum.reduce([xx, yy, (inner_w - 1) - xx, (inner_h - 1) - yy])
    band = Image.fromarray((a * np.clip(d / 24.0, 0.0, 1.0)[:, :, None] ** 0.8).astype(np.uint8))

    # 灰黑背景板（软边 + 上亮下暗，像一块有厚度的板）
    mask = Image.new("L", (CANVAS_W, CANVAS_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [2, 2, CANVAS_W - 3, CANVAS_H - 3], radius=PANEL_RADIUS, fill=PANEL_ALPHA
    )
    mask = mask.filter(ImageFilter.GaussianBlur(EDGE_FEATHER * 0.5))
    # 再乘一层"到边距离"衰减，保证贴图四条边 alpha 一定是 0
    # （只靠圆角模糊不够：实测四边仍残留 alpha=150，换到房间上就是一圈硬切）
    my, mx = np.mgrid[0:CANVAS_H, 0:CANVAS_W].astype(np.float32)
    md = np.minimum.reduce([mx, my, (CANVAS_W - 1) - mx, (CANVAS_H - 1) - my])
    mask = Image.fromarray(
        (np.array(mask).astype(np.float32) * np.clip(md / EDGE_FEATHER, 0.0, 1.0) ** 1.2).astype(np.uint8)
    )
    grad = np.linspace(1.12, 0.90, CANVAS_H).reshape(-1, 1, 1)
    panel_rgb = np.zeros((CANVAS_H, CANVAS_W, 3), np.float32)
    panel_rgb[:] = np.array(PANEL_RGB, np.float32)
    panel_rgb = np.clip(panel_rgb * grad, 0, 255).astype(np.uint8)   # (H,1,1) 广播到整幅板面
    panel = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    panel.paste(Image.fromarray(panel_rgb, "RGB"), (0, 0), mask)
    panel.putalpha(mask)

    tmp = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    tmp.paste(band, (INSET, INSET))
    out = Image.alpha_composite(panel, tmp)
    out.save(args.out)

    arr = np.array(out)
    print(f"saved {args.out}  size={out.size}  板面不透明占比={float((arr[:,:,3]>200).mean())*100:.1f}%  "
          f"四边alpha={arr[:,0,3].max()}/{arr[:,-1,3].max()}/{arr[0,:,3].max()}/{arr[-1,:,3].max()}")
    print(f"  六道光点（板内坐标）：{[(int(x*sx)+INSET, int(y*sy)+INSET) for x, y in LIGHTS]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
