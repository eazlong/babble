#!/usr/bin/env python3
"""
将图片中指定颜色转换为透明。

用法:
    python color_to_transparent.py input.png -c "#00FF00" -o output.png
    python color_to_transparent.py input.png -c "255,0,255" -t 30 -o output.png
"""

import argparse
import sys
from pathlib import Path

from PIL import Image


def parse_color(color_str: str) -> tuple[int, int, int]:
    """解析颜色字符串，支持 HEX (#RRGGBB) 和 RGB (R,G,B) 格式。"""
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


def color_distance(c1: tuple[int, int, int], c2: tuple[int, int, int]) -> float:
    """计算两个 RGB 颜色的欧氏距离。"""
    return ((c1[0] - c2[0]) ** 2 + (c1[1] - c2[1]) ** 2 + (c1[2] - c2[2]) ** 2) ** 0.5


def replace_color_to_transparent(
    img: Image.Image, target: tuple[int, int, int], tolerance: float
) -> Image.Image:
    """将图像中匹配目标颜色（在容差范围内）的像素设为透明。"""
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    r, g, b, a = img.split()
    pixels = img.load()
    width, height = img.size

    for y in range(height):
        for x in range(width):
            pr, pg, pb, pa = pixels[x, y]
            if color_distance((pr, pg, pb), target) <= tolerance:
                pixels[x, y] = (pr, pg, pb, 0)

    return img


def main() -> int:
    parser = argparse.ArgumentParser(description="将图片中指定颜色转换为透明")
    parser.add_argument("input", type=Path, help="输入图片路径")
    parser.add_argument(
        "-c",
        "--color",
        required=True,
        help="目标颜色，格式: #RRGGBB 或 R,G,B (例: '#00FF00' 或 '0,255,0')",
    )
    parser.add_argument(
        "-t",
        "--tolerance",
        type=float,
        default=0.0,
        help="颜色容差 (0 = 精确匹配, 默认: 0, 建议范围: 0-50)",
    )
    parser.add_argument(
        "-o", "--output", type=Path, help="输出路径 (默认: 输入文件名_transparent.png)"
    )
    args = parser.parse_args()

    if not args.input.exists():
        print(f"错误: 输入文件不存在: {args.input}", file=sys.stderr)
        return 1

    try:
        target = parse_color(args.color)
    except ValueError as e:
        print(f"错误: {e}", file=sys.stderr)
        return 1

    output = args.output or args.input.with_name(
        f"{args.input.stem}_transparent.png"
    )

    try:
        img = Image.open(args.input)
    except Exception as e:
        print(f"错误: 无法打开图片: {e}", file=sys.stderr)
        return 1

    result = replace_color_to_transparent(img, target, args.tolerance)

    try:
        result.save(output, format="PNG")
    except Exception as e:
        print(f"错误: 保存失败: {e}", file=sys.stderr)
        return 1

    print(f"已保存: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
