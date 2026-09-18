"""清除抠图残留的"游离半透明像素"。

现象：rembg 处理带渐变/污渍背景的生成图时，会把一部分背景留在 alpha 16..250，
表现为贴在游戏底图上时、家具**轮廓之外**的墙上出现一块淡灰色污迹。
（不同于正常抗锯齿：正常边缘在实心核心 1-3px 内。）

判据：半透明像素到"最近不透明像素"的距离 > --max-dist（默认 5px）即判为残留，alpha 归零。
因底部接触影也是"远离主体的半透明像素"，本工具必须在**加影之前**对抠好的图运行。
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def clean(p: Path, out_dir: Path, max_dist: int) -> None:
    im = Image.open(p).convert("RGBA")
    a = np.array(im)
    al = a[:, :, 3]
    opaque = al >= 250
    if not opaque.any():
        print(f"skip (no opaque core): {p.name}")
        return
    dist = ndimage.distance_transform_edt(np.logical_not(opaque))
    stray = np.logical_and(np.logical_and(al > 0, al < 250), dist > max_dist)
    n = int(stray.sum())
    a[:, :, 3] = np.where(stray, 0, al)
    out_dir.mkdir(parents=True, exist_ok=True)
    Image.fromarray(a).save(out_dir / p.name)
    print(f"{p.name}: 清除游离半透明像素 {n}px (距主体>{max_dist}px)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", required=True, help="输入目录")
    ap.add_argument("-o", "--out", required=True, help="输出目录")
    ap.add_argument("--max-dist", type=int, default=5)
    args = ap.parse_args()
    inp, out = Path(args.batch), Path(args.out)
    files = sorted(f for f in inp.glob("*.png") if not f.name.endswith(".import"))
    for f in files:
        clean(f, out, args.max_dist)
    print(f"Batch complete: {len(files)} files -> {out}")


if __name__ == "__main__":
    main()
