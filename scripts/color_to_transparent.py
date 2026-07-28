#!/usr/bin/env python3
"""
将图片中指定颜色转换为透明。支持单文件或整个文件夹批量处理。

用法:
    python color_to_transparent.py input.png -c "#00FF00" -o output.png
    python color_to_transparent.py input.png -c "255,0,255" -t 30 -o output.png
    python color_to_transparent.py assets/ -c "#00FF00" -o out/
    python color_to_transparent.py assets/ -c "#00FF00" --in-place
"""

import argparse
import sys
from pathlib import Path

from PIL import Image

IMAGE_EXTS = {".png", ".bmp", ".gif", ".webp", ".tiff"}


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


def process_one(
    src: Path,
    target: tuple[int, int, int],
    tolerance: float,
    output: Path,
) -> bool:
    """处理单个图片文件，成功返回 True。"""
    try:
        img = Image.open(src)
    except Exception as e:
        print(f"错误: 无法打开图片 {src}: {e}", file=sys.stderr)
        return False

    result = replace_color_to_transparent(img, target, tolerance)

    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        result.save(output, format="PNG")
    except Exception as e:
        print(f"错误: 保存失败 {output}: {e}", file=sys.stderr)
        return False

    print(f"已保存: {output}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="将图片中指定颜色转换为透明 (支持单文件或文件夹批量处理)")
    parser.add_argument("input", type=Path, help="输入图片路径或文件夹")
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
        "-o", "--output", type=Path, help="输出路径: 文件或文件夹 (默认: 单文件加后缀; 文件夹存入 _transparent 子目录)"
    )
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="覆盖原文件 (仅文件夹模式有效; 慎用)",
    )
    args = parser.parse_args()

    if not args.input.exists():
        print(f"错误: 输入路径不存在: {args.input}", file=sys.stderr)
        return 1

    try:
        target = parse_color(args.color)
    except ValueError as e:
        print(f"错误: {e}", file=sys.stderr)
        return 1

    # 单文件模式
    if args.input.is_file():
        output = args.output or args.input.with_name(
            f"{args.input.stem}_transparent.png"
        )
        return 0 if process_one(args.input, target, args.tolerance, output) else 1

    # 文件夹批量模式
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
        # 保持原相对子目录结构；非 in-place 时输出为 PNG 并加后缀
        rel = p.relative_to(args.input)
        out_name = p.name if args.in_place else f"{p.stem}_transparent.png"
        out_path = out_dir / rel.parent / out_name
        if process_one(p, target, args.tolerance, out_path):
            success += 1

    print(f"完成: {success}/{len(files)} 个文件成功")
    return 0 if success == len(files) else 1


if __name__ == "__main__":
    sys.exit(main())
