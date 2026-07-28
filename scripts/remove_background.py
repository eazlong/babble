#!/usr/bin/env python3
"""
理想的去背景脚本。

针对黑色（或近黑）背景，使用 alpha matting（un-premultiply）还原真实颜色与透明度，
消除“颜色匹配 + 容差”方式留下的黑边 / 光晕残留。

原理：物体渲染到黑底上时 observed = src * alpha，
故 alpha = max(r,g,b)/255，src = observed / alpha。

用法:
    # 黑色背景：alpha matting 模式（推荐）
    python remove_background.py input.png --black -o output.png
    python remove_background.py input.png --black -t 10 -o output.png

    # 指定颜色背景：按色键抠图（带羽化，避免锯齿）
    python remove_background.py input.png -c "#00FF00" -t 30 -o output.png

    # 文件夹批量
    python remove_background.py assets/ --black -o out/
    python remove_background.py assets/ -c "#00FF00" --in-place
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

IMAGE_EXTS = {".png", ".bmp", ".gif", ".webp", ".tiff"}


def parse_color(color_str: str) -> tuple[int, int, int]:
    color_str = color_str.strip()
    if color_str.startswith("#"):
        color_str = color_str[1:]
        if len(color_str) != 6:
            raise ValueError("HEX 颜色必须为 #RRGGBB 格式")
        return (
            int(color_str[0:2], 16),
            int(color_str[2:4], 16),
            int(color_str[4:6], 16),
        )
    if "," in color_str:
        parts = [p.strip() for p in color_str.split(",")]
        if len(parts) != 3:
            raise ValueError("RGB 颜色必须为 R,G,B 格式")
        r, g, b = (int(p) for p in parts)
        for v in (r, g, b):
            if not 0 <= v <= 255:
                raise ValueError("RGB 分量必须在 0-255 之间")
        return (r, g, b)
    raise ValueError("无法解析颜色，使用 #RRGGBB 或 R,G,B 格式")


def remove_black_background(img: Image.Image, bg_lo: int, edge_hi: int) -> Image.Image:
    """
    黑背景抠图（三段式，主体保持不透明）：
      - maxc <= bg_lo        : 纯背景，alpha=0
      - bg_lo < maxc < edge_hi: 边缘过渡，软 alpha + un-premultiply 还原颜色（消除黑边）
      - maxc >= edge_hi       : 主体，alpha=255，保留原色

    bg_lo: 视为纯黑背景的亮度阈值（建议 4-16）。
    edge_hi: 边缘过渡区上界，高于此值视为纯主体（建议 40-80）。
    """
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    arr = np.asarray(img).astype(np.float32)
    rgb = arr[..., :3]

    maxc = rgb.max(axis=2)  # 0..255
    # 软 alpha：bg_lo 以下为 0，edge_hi 以上为 255，中间线性过渡
    alpha = np.clip((maxc - bg_lo) / (edge_hi - bg_lo), 0.0, 1.0) * 255.0

    # 对边缘半透明像素 un-premultiply 还原真实颜色，消除黑边
    alpha_norm = alpha / 255.0
    safe = np.clip(alpha_norm, 1e-6, 1.0)[..., None]
    src = np.clip(rgb / safe, 0, 255)

    out = np.empty((arr.shape[0], arr.shape[1], 4), dtype=np.float32)
    out[..., :3] = src
    out[..., 3] = alpha
    return Image.fromarray(out.astype(np.uint8), mode="RGBA")


def remove_color_background(
    img: Image.Image, target: tuple[int, int, int], tolerance: float, feather: int
) -> Image.Image:
    """
    指定颜色背景：按欧氏距离生成软 alpha（羽化），避免硬边锯齿。
    distance <= tolerance -> alpha=0；distance >= tolerance+feather -> alpha=255。
    """
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    arr = np.asarray(img).astype(np.float32)
    rgb = arr[..., :3]
    t = np.array(target, dtype=np.float32)

    dist = np.sqrt(((rgb - t) ** 2).sum(axis=2))
    low = tolerance
    high = tolerance + max(feather, 1)
    alpha = np.clip((dist - low) / (high - low), 0.0, 1.0) * 255.0

    out = np.empty((arr.shape[0], arr.shape[1], 4), dtype=np.float32)
    out[..., :3] = rgb
    out[..., 3] = alpha
    return Image.fromarray(out.astype(np.uint8), mode="RGBA")


def process_one(src: Path, fn, output: Path) -> bool:
    try:
        img = Image.open(src)
    except Exception as e:
        print(f"错误: 无法打开图片 {src}: {e}", file=sys.stderr)
        return False

    result = fn(img)
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        result.save(output, format="PNG")
    except Exception as e:
        print(f"错误: 保存失败 {output}: {e}", file=sys.stderr)
        return False

    print(f"已保存: {output}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="理想的去背景脚本 (黑背景 alpha matting / 指定色键抠图)")
    parser.add_argument("input", type=Path, help="输入图片路径或文件夹")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--black", action="store_true", help="黑背景模式 (alpha matting, 推荐)")
    mode.add_argument("-c", "--color", help="指定背景色: #RRGGBB 或 R,G,B")
    parser.add_argument("-t", "--tolerance", type=float, default=8.0,
                        help="黑背景: 视为纯黑背景的亮度阈值(0-255, 建议 4-16); 色键: 颜色容差(建议 0-60)")
    parser.add_argument("--edge", type=int, default=60,
                        help="黑背景: 边缘过渡区上界(0-255, 建议 40-80)，高于此值视为纯主体保持不透明")
    parser.add_argument("--feather", type=int, default=8, help="色键模式羽化宽度(像素距离, 默认 8)")
    parser.add_argument("-o", "--output", type=Path, help="输出路径 (文件或文件夹)")
    parser.add_argument("--in-place", action="store_true", help="覆盖原文件 (仅文件夹模式; 慎用)")
    args = parser.parse_args()

    if not args.input.exists():
        print(f"错误: 输入路径不存在: {args.input}", file=sys.stderr)
        return 1

    if args.black:
        edge = max(int(args.edge), int(args.tolerance) + 1)
        fn = lambda im: remove_black_background(im, int(args.tolerance), edge)
    else:
        try:
            target = parse_color(args.color)
        except ValueError as e:
            print(f"错误: {e}", file=sys.stderr)
            return 1
        fn = lambda im: remove_color_background(im, target, args.tolerance, args.feather)

    if args.input.is_file():
        output = args.output or args.input.with_name(f"{args.input.stem}_transparent.png")
        return 0 if process_one(args.input, fn, output) else 1

    if args.in_place and args.output is not None:
        print("错误: --in-place 与 -o/--output 不可同时使用", file=sys.stderr)
        return 1

    if args.in_place:
        out_dir = args.input
    else:
        out_dir = args.output or args.input / "_transparent"
        out_dir.mkdir(parents=True, exist_ok=True)

    files = [p for p in sorted(args.input.rglob("*")) if p.suffix.lower() in IMAGE_EXTS]
    if not files:
        print(f"提示: 文件夹内未找到图片: {args.input}", file=sys.stderr)
        return 0

    success = 0
    for p in files:
        rel = p.relative_to(args.input)
        out_name = p.name if args.in_place else f"{p.stem}_transparent.png"
        out_path = out_dir / rel.parent / out_name
        if process_one(p, fn, out_path):
            success += 1

    print(f"完成: {success}/{len(files)} 个文件成功")
    return 0 if success == len(files) else 1


if __name__ == "__main__":
    sys.exit(main())
