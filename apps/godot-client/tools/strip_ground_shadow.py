"""剥离角色脚下的"地面投影椭圆"（须在 harden_alpha 之前运行）。

为什么需要：SOP-C-alt 实测——即使 prompt 写了 no ground shadow / no ellipse，
图像模型仍会在角色脚下画一个灰色椭圆；rembg 会把它当主体保留。

**判据（实测 6/6 通用，且与颜色/亮度无关）：**
    角色本体是**不透明**的（alpha ≈ 255），脚下的投影是**半透明**的
    （行内最大 alpha 仅 ~110–200）。因此「最后一个含 alpha≥250 像素的行」
    就是角色的落脚线，其下即投影。
    —— 故本工具**必须在 harden_alpha 之前**运行：harden_alpha 会把投影的
    半透明 alpha 顶到 255，判据即失效（残留会变成可见灰块）。

护栏：仅当待切除区"扁"（高度 < 0.35 × 其最大宽度）时才切，
避免误切角色的半透明软下摆（那种区域是竖长的）。

用法：
    python tools/strip_ground_shadow.py <in.png> -o <out.png>
    python tools/strip_ground_shadow.py --batch <dir> -o <out_dir>
    python tools/strip_ground_shadow.py --batch <dir> --dry-run
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image

SOLID_ALPHA = 250     # 角色本体判定阈值
MIN_DROP_ROWS = 3     # 至少切掉这么多行才算投影
MAX_FLATNESS = 0.35   # 待切除区 高/宽 上限（投影是扁的）


def find_shadow_cut_row(alpha: np.ndarray) -> tuple[int | None, str]:
    solid_per_row = (alpha >= SOLID_ALPHA).sum(axis=1)
    rows = np.nonzero(solid_per_row)[0]
    if rows.size == 0:
        return None, "no-solid-core"

    last_solid = int(rows[-1])
    bottom = int(np.nonzero((alpha > 16).sum(axis=1))[0][-1]) if (alpha > 16).any() else last_solid
    depth = bottom - last_solid
    if depth < MIN_DROP_ROWS:
        return None, "no-shadow"

    region = alpha[last_solid + 1: bottom + 1]
    width = int((region > 16).sum(axis=1).max()) if region.size else 0
    if width == 0:
        return None, "no-shadow"
    if depth > MAX_FLATNESS * width:
        return None, f"skip-not-flat(h{depth}>0.35*w{width})"

    return last_solid, f"cut-below-row-{last_solid}(drop {depth}px)"


def strip_one(src: str, dst: str | None, dry_run: bool = False) -> str:
    img = Image.open(src).convert("RGBA")
    alpha = np.asarray(img.split()[-1]).copy()
    cut, verdict = find_shadow_cut_row(alpha)

    if cut is not None:
        # 保留 1 行羽化，避免留下硬切边
        alpha[cut + 2:] = 0

    if not dry_run and dst:
        out = img.copy()
        out.putalpha(Image.fromarray(alpha))
        os.makedirs(os.path.dirname(os.path.abspath(dst)) or ".", exist_ok=True)
        out.save(dst)
    return verdict


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", nargs="?")
    ap.add_argument("-o", "--output")
    ap.add_argument("--batch")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.batch:
        os.makedirs(args.output or "/tmp", exist_ok=True)
        for f in sorted(x for x in os.listdir(args.batch) if x.lower().endswith(".png")):
            out = None if args.dry_run else os.path.join(args.output, f)
            print(f"{f}: {strip_one(os.path.join(args.batch, f), out, args.dry_run)}")
        return 0

    if not args.input:
        ap.error("需要 input 或 --batch")
    print(f"{os.path.basename(args.input)}: {strip_one(args.input, args.output, args.dry_run)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
