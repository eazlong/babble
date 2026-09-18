"""把精灵裁到"实心主体 + 少量余量"，抹掉外围的柔和光晕/雾气。

为什么需要：图像模型偶尔会在角色周围画一圈黄色 glow（即使 prompt 里写了
no glow / no aura）。这类光晕在 rembg 里会被当主体保留，harden_alpha 也
只能削弱、不能清除（实测：半透明像素占比 10.5%，而正常帧约 1.7%）。

做法（确定性，不看颜色）：
    1. 取 alpha >= --solid 的像素作为"实心主体"；
    2. 用 MaxFilter 膨胀 --pad 像素（给角色自身抗锯齿边留余量）；
    3. 膨胀掩膜之外的 alpha 一律置 0。

用法：
    python tools/clip_halo.py in.png -o out.png --solid 200 --pad 4
    python tools/clip_halo.py --batch in_dir -o out_dir --solid 200 --pad 4
"""

import argparse
import glob
import os
import sys

from PIL import Image, ImageFilter

def clip(path, out, solid, pad):
    im = Image.open(path).convert("RGBA")
    a = im.getchannel("A")
    # 实心掩膜（>=solid 的像素为 255）
    mask = a.point(lambda v: 255 if v >= solid else 0, mode="L")
    # 膨胀：MaxFilter(size=2*pad+1) 近似 pad 像素膨胀
    k = max(3, 2 * pad + 1)
    if k % 2 == 0:
        k += 1
    grown = mask.filter(ImageFilter.MaxFilter(k))
    new_a = Image.composite(a, Image.new("L", a.size, 0), grown)
    im.putalpha(new_a)
    im.save(out)
    return im, new_a

def main():
    ap = argparse.ArgumentParser(description="Clip sprite to its solid core (removes halo/glow)")
    ap.add_argument("input", nargs="?", help="input PNG")
    ap.add_argument("-o", "--output", help="output PNG (or directory with --batch)")
    ap.add_argument("--batch", help="process every PNG in this directory")
    ap.add_argument("--solid", type=int, default=200, help="alpha >= solid counts as body (default 200)")
    ap.add_argument("--pad", type=int, default=4, help="dilation padding in px for edge AA (default 4)")
    args = ap.parse_args()

    if args.batch:
        files = sorted(glob.glob(os.path.join(args.batch, "*.png")))
        if not files:
            print(f"no PNG in {args.batch}")
            return 1
        os.makedirs(args.output, exist_ok=True)
        for f in files:
            _, na = clip(f, os.path.join(args.output, os.path.basename(f)), args.solid, args.pad)
            import numpy as np
            arr = np.asarray(na)
            semi = ((arr > 16) & (arr < 200)).mean() * 100
            print(f"clipped {os.path.basename(f)}  semitransparent={semi:.2f}%")
    else:
        if not args.input or not args.output:
            print("need input and -o output")
            return 1
        clip(args.input, args.output, args.solid, args.pad)
        print(f"clipped {os.path.basename(args.input)} -> {args.output}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
