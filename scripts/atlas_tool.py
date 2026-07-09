#!/usr/bin/env python3
"""
atlas_tool.py — 图集拆分 & 打包工具

功能：
  1. 拆分：将一张大 PNG（内含 N×N 规则网格小图）切成独立小图
  2. 打包：将一组小图重新拼成正方形/矩形大图集，并输出描述文件

支持输出格式：
  - JSON（通用，含每张小图的 x/y/w/h）
  - Godot .tres（AtlasTexture 格式，可在 Godot 4.6 编辑器中直接使用）

依赖：
  pip install Pillow

用法示例：
  # 拆分一张 3×3 的大图
  python atlas_tool.py split sprites.png --grid 3 --out-dir ./sprites_split

  # 将一组小图打包成图集（自动计算尺寸）
  python atlas_tool.py pack ./sprites_split/*.png --cell 128 --out atlas.png

  # 指定输出网格（4列×N行）
  python atlas_tool.py pack ./sprites_split/*.png --cell 128 --cols 4 --out atlas.png
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("需要安装 Pillow：pip install Pillow")


# ─────────────────────────── 拆分 ───────────────────────────


def split_atlas(
    src: Path,
    grid: int,
    out_dir: Path,
    padding: int = 0,
    prefix: str = "",
) -> list[dict]:
    """
    将 src 按 grid×grid 切成小图，输出到 out_dir。
    padding: 每个格子四周的内边距（像素），用于去除可能的边框/描边
    返回每张小图的信息列表。
    """
    img = Image.open(src).convert("RGBA")
    cell_w = img.width // grid
    cell_h = img.height // grid

    if img.width % grid != 0 or img.height % grid != 0:
        print(
            f"警告：图片尺寸 {img.width}x{img.height} 不能被 {grid} 整除，"
            f"实际单格 = {cell_w}x{cell_h}，可能裁切不全。",
            file=sys.stderr,
        )

    out_dir.mkdir(parents=True, exist_ok=True)
    entries: list[dict] = []

    stem = src.stem
    for row in range(grid):
        for col in range(grid):
            idx = row * grid + col
            name = f"{prefix}{stem}_{idx:03d}_r{row}_c{col}.png"
            x0 = col * cell_w + padding
            y0 = row * cell_h + padding
            x1 = (col + 1) * cell_w - padding
            y1 = (row + 1) * cell_h - padding
            tile = img.crop((x0, y0, x1, y1))
            tile.save(out_dir / name)
            entries.append(
                {
                    "name": Path(name).stem,
                    "file": name,
                    "grid_row": row,
                    "grid_col": col,
                    "src_x": x0,
                    "src_y": y0,
                    "w": x1 - x0,
                    "h": y1 - y0,
                }
            )

    print(f"已拆分 {len(entries)} 张小图 → {out_dir}")
    return entries


# ─────────────────────────── 打包 ───────────────────────────


def pack_atlas(
    inputs: list[Path],
    cell_size: int | None,
    out_path: Path,
    cols: int | None = None,
    padding: int = 1,
    bg_color: tuple[int, int, int, int] = (0, 0, 0, 0),
) -> tuple[Image.Image, list[dict]]:
    """
    将一组小图拼成一张大图集。

    cell_size: 统一每张小图的尺寸（会强制缩放）；None 则用每图原始尺寸（要求全部等大）
    cols: 指定列数；None 则自动算成最接近正方形的网格
    padding: 小图之间的间距（像素）
    bg_color: 背景填充色（RGBA）
    """
    tiles: list[tuple[str, Image.Image]] = []
    for p in sorted(inputs):
        if p.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"}:
            continue
        im = Image.open(p).convert("RGBA")
        if cell_size is not None and (im.width != cell_size or im.height != cell_size):
            im = im.resize((cell_size, cell_size), Image.NEAREST)
        tiles.append((p.stem, im))

    if not tiles:
        sys.exit("没有找到任何有效图片。")

    # 验证尺寸一致性（cell_size=None 时）
    sizes = {im.size for _, im in tiles}
    if cell_size is None:
        if len(sizes) > 1:
            sys.exit(
                f"小图尺寸不一致：{sizes}。请用 --cell 指定统一尺寸，或先缩放。"
            )
        tw, th = sizes.pop()
    else:
        tw = th = cell_size

    n = len(tiles)
    if cols is None:
        cols = math.ceil(math.sqrt(n))
    rows = math.ceil(n / cols)

    atlas_w = cols * tw + (cols + 1) * padding
    atlas_h = rows * th + (rows + 1) * padding
    atlas = Image.new("RGBA", (atlas_w, atlas_h), bg_color)

    entries: list[dict] = []
    for idx, (name, im) in enumerate(tiles):
        r, c = divmod(idx, cols)
        x = padding + c * (tw + padding)
        y = padding + r * (th + padding)
        atlas.paste(im, (x, y), im if im.mode == "RGBA" else None)
        entries.append(
            {
                "name": name,
                "x": x,
                "y": y,
                "w": tw,
                "h": th,
                "index": idx,
            }
        )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(out_path)
    print(f"已生成图集 {out_path}（{cols}×{rows}，{atlas_w}x{atlas_h}）")
    return atlas, entries


# ─────────────────────────── 描述文件 ───────────────────────────


def write_json(entries: list[dict], atlas_path: Path, json_path: Path) -> None:
    """输出通用 JSON 描述文件。"""
    data = {
        "image": atlas_path.name,
        "width": 0,
        "height": 0,
        "sprites": entries,
    }
    # 回填图集尺寸
    with Image.open(atlas_path) as im:
        data["width"] = im.width
        data["height"] = im.height

    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    print(f"已写入 JSON → {json_path}")


def write_godot_tres(
    entries: list[dict],
    atlas_path: Path,
    tres_dir: Path,
    res_path_prefix: str = "res://assets/sprites/",
) -> list[Path]:
    """
    为每个 sprite 输出一个独立的 Godot 4.x .tres 文件（AtlasTexture），
    指向同一张图集 PNG。Godot 编辑器中可直接拖入使用。
    """
    tres_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    atlas_ref = f"{res_path_prefix}{atlas_path.name}"

    for e in entries:
        # Godot AtlasTexture 的 region = Rect2(x, y, w, h)
        region = f"Rect2({e['x']}, {e['y']}, {e['w']}, {e['h']})"
        content = (
            "[gd_resource type=\"AtlasTexture\" format=3]\n\n"
            "[ext_resource type=\"Texture2D\" path=\"{atlas}\" id=\"1\"]\n\n"
            "[resource]\n"
            "atlas = ExtResource(\"1\")\n"
            "region = {region}\n"
            "margin = Rect2(0, 0, 0, 0)\n".format(atlas=atlas_ref, region=region)
        )
        p = tres_dir / f"{e['name']}.tres"
        p.write_text(content)
        written.append(p)

    print(f"已写入 {len(written)} 个 Godot .tres → {tres_dir}")
    return written


# ─────────────────────────── CLI ───────────────────────────


def cmd_split(args: argparse.Namespace) -> None:
    src = Path(args.src).expanduser()
    if not src.exists():
        sys.exit(f"源文件不存在：{src}")
    out_dir = Path(args.out_dir) if args.out_dir else Path.cwd() / f"{src.stem}_split"
    split_atlas(src, args.grid, out_dir, padding=args.padding, prefix=args.prefix)


def cmd_pack(args: argparse.Namespace) -> None:
    inputs = [Path(p).expanduser() for p in args.inputs]
    missing = [p for p in inputs if not p.exists()]
    if missing:
        sys.exit(f"找不到文件：{missing[:3]}...")

    out_path = Path(args.out)
    pack_atlas(inputs, args.cell, out_path, cols=args.cols, padding=args.padding)

    json_path = out_path.with_suffix(".json")
    # 重新读取 entries（pack 已打印过，这里再算一次用于输出）
    entries = _repack_entries(inputs, args.cell, args.cols, args.padding)
    write_json(entries, out_path, json_path)

    if args.godot:
        tres_dir = out_path.parent / f"{out_path.stem}_tres"
        write_godot_tres(
            entries,
            out_path,
            tres_dir,
            res_path_prefix=args.godot_res_path,
        )


def _repack_entries(
    inputs: list[Path],
    cell_size: int | None,
    cols: int | None,
    padding: int,
) -> list[dict]:
    """复算一次打包坐标（用于输出描述文件）。"""
    filtered = sorted(
        p for p in inputs if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
    )
    tw = th = cell_size if cell_size else Image.open(filtered[0]).size[0]
    n = len(filtered)
    if cols is None:
        cols = math.ceil(math.sqrt(n))
    entries: list[dict] = []
    for idx, p in enumerate(filtered):
        r, c = divmod(idx, cols)
        x = padding + c * (tw + padding)
        y = padding + r * (th + padding)
        entries.append({"name": p.stem, "x": x, "y": y, "w": tw, "h": th, "index": idx})
    return entries


def cmd_info(args: argparse.Namespace) -> None:
    """打印一张图集的尺寸和网格信息，辅助判断拆分参数。"""
    p = Path(args.src).expanduser()
    with Image.open(p) as im:
        w, h = im.size
    print(f"{p.name}: {w}x{h}")
    for g in (3, 4, 5, 6, 8):
        if w % g == 0 and h % g == 0:
            print(f"  {g}×{g} 网格 → 每格 {w//g}x{h//g}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="atlas_tool",
        description="图集拆分 & 打包工具（含 Godot .tres 输出）",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    # split
    s = sub.add_parser("split", help="将一张 N×N 大图拆成小图")
    s.add_argument("src", help="源 PNG 路径")
    s.add_argument("--grid", "-g", type=int, required=True, help="网格维度（如 3 表示 3×3）")
    s.add_argument("--out-dir", "-o", help="输出目录（默认 ./<stem>_split）")
    s.add_argument("--padding", "-p", type=int, default=0, help="每格四周裁切像素（去边框）")
    s.add_argument("--prefix", default="", help="输出文件名前缀")
    s.set_defaults(func=cmd_split)

    # pack
    s = sub.add_parser("pack", help="将一组小图拼成图集，输出 PNG + JSON + 可选 .tres")
    s.add_argument("inputs", nargs="+", help="小图路径（支持 glob，如 sprites/*.png）")
    s.add_argument("--out", "-o", required=True, help="输出图集路径，如 atlas.png")
    s.add_argument("--cell", "-c", type=int, help="统一单格尺寸（像素），小图会被缩放")
    s.add_argument("--cols", type=int, help="指定列数（默认自动算成接近正方形）")
    s.add_argument("--padding", "-p", type=int, default=1, help="小图间距（像素）")
    s.add_argument(
        "--godot", action="store_true", help="同时输出 Godot 4.x .tres AtlasTexture 文件"
    )
    s.add_argument(
        "--godot-res-path",
        default="res://assets/sprites/",
        help="Godot .tres 中图集的 res:// 路径前缀",
    )
    s.set_defaults(func=cmd_pack)

    # info
    s = sub.add_parser("info", help="查看一张图的尺寸和可整除网格")
    s.add_argument("src", help="PNG 路径")
    s.set_defaults(func=cmd_info)

    return p


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
