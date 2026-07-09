#!/usr/bin/env python3
"""按比例缩放图片(支持单文件或整个文件夹)

用法:
    # 单文件
    python resize_image.py photo.jpg -o out.jpg --scale 0.5

    # 整个文件夹(非递归,只处理当前目录)
    python resize_image.py ./photos -o ./out --width 800

    # 递归处理子文件夹(保留目录结构)
    python resize_image.py ./photos -o ./out --max-side 1024 -r

    # 只处理指定扩展名
    python resize_image.py ./photos -o ./out --scale 0.5 --ext .jpg .png
"""
import argparse
from pathlib import Path
from PIL import Image


DEFAULT_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tiff", ".tif"}


def resize_by_scale(img: Image.Image, scale: float) -> Image.Image:
    w, h = img.size
    return img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)


def resize_by_width(img: Image.Image, width: int) -> Image.Image:
    return resize_by_scale(img, width / img.size[0])


def resize_by_height(img: Image.Image, height: int) -> Image.Image:
    return resize_by_scale(img, height / img.size[1])


def resize_max_side(img: Image.Image, max_side: int) -> Image.Image:
    w, h = img.size
    cur_max = max(w, h)
    if cur_max <= max_side:
        return img.copy()
    return resize_by_scale(img, max_side / cur_max)


def compute_resize(img: Image.Image, args) -> Image.Image:
    if args.scale is not None:
        return resize_by_scale(img, args.scale)
    if args.width is not None:
        return resize_by_width(img, args.width)
    if args.height is not None:
        return resize_by_height(img, args.height)
    return resize_max_side(img, args.max_side)


def save_kwargs_for(suffix: str, args) -> dict:
    if suffix.lower() in {".jpg", ".jpeg", ".webp"}:
        return {"quality": args.quality}
    return {}


def process_file(src: Path, dst: Path, args) -> tuple[bool, str]:
    try:
        with Image.open(src) as img:
            if dst.suffix.lower() in {".jpg", ".jpeg"}:
                img = img.convert("RGB")
            result = compute_resize(img, args)
            dst.parent.mkdir(parents=True, exist_ok=True)
            result.save(dst, **save_kwargs_for(dst.suffix, args))
        return True, f"{src} -> {dst} ({result.size[0]}x{result.size[1]})"
    except Exception as e:
        return False, f"跳过 {src}: {e}"


def iter_files(input_dir: Path, exts: set[str], recursive: bool):
    walker = input_dir.rglob if recursive else input_dir.glob
    for p in walker("*"):
        if p.is_file() and p.suffix.lower() in exts:
            yield p


def main():
    parser = argparse.ArgumentParser(description="按比例缩放图片或整个文件夹")
    parser.add_argument("input", type=Path, help="输入文件或目录")
    parser.add_argument("-o", "--output", type=Path, required=True, help="输出文件(单文件)或目录(批量)")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--scale", type=float, help="缩放比例,如 0.5")
    group.add_argument("--width", type=int, help="目标宽度(像素)")
    group.add_argument("--height", type=int, help="目标高度(像素)")
    group.add_argument("--max-side", type=int, help="最长边限制")
    parser.add_argument("-r", "--recursive", action="store_true", help="递归处理子目录(保留目录结构)")
    parser.add_argument("--ext", nargs="+", help="仅处理指定扩展名,如 --ext .jpg .png")
    parser.add_argument("-q", "--quality", type=int, default=85, help="JPEG/WebP 质量 (1-100)")
    parser.add_argument("--overwrite", action="store_true", help="覆盖已存在的输出文件")
    args = parser.parse_args()

    if not args.input.exists():
        raise SystemExit(f"输入不存在: {args.input}")

    # 单文件模式
    if args.input.is_file():
        ok, msg = process_file(args.input, args.output, args)
        print(msg)
        raise SystemExit(0 if ok else 1)

    # 文件夹模式
    exts = {e.lower() if e.startswith(".") else f".{e.lower()}" for e in args.ext} if args.ext else DEFAULT_EXTS
    files = list(iter_files(args.input, exts, args.recursive))
    if not files:
        print(f"在 {args.input} 中未找到图片")
        return

    ok_count, fail_count = 0, 0
    for src in files:
        rel = src.relative_to(args.input)
        dst = args.output / rel
        if dst.exists() and not args.overwrite:
            print(f"跳过(已存在): {dst}")
            continue
        ok, msg = process_file(src, dst, args)
        print(msg)
        if ok:
            ok_count += 1
        else:
            fail_count += 1

    print(f"\n完成: 成功 {ok_count}, 失败/跳过 {fail_count}, 共 {len(files)}")


if __name__ == "__main__":
    main()
