"""抠图孔洞检测：找出物体内部被不透明像素完全包围的半透明/透明区。

存在的意义：rembg 会把物料里"浅色"的部分（如柜内浅色隔板）误判成背景挖掉，
表现为游戏里从家具内部透出房间背景。只看整体半透明占比会被"物件外的透明区"
和"底部接触影"污染，所以用连通域判据：从画面四边扩散能到达的算外部，
到不了的非实心像素才是真孔洞。
"""
from PIL import Image
import numpy as np
from scipy import ndimage

F = "tmp/asset-gen/bfp/final"
for lab, fn, base_cut in [("书柜闭", "bookshelf_closed.png", 26),
                          ("衣橱", "wardrobe_empty.png", 26)]:
    a = np.array(Image.open(f"{F}/{fn}").convert("RGBA"))
    a = a[:-base_cut]                      # 排除底部接触影
    al = a[:, :, 3]
    solid = al >= 250
    free = np.logical_not(solid)
    lab_img, n = ndimage.label(free)
    border = set(lab_img[0, :]) | set(lab_img[-1, :]) | set(lab_img[:, 0]) | set(lab_img[:, -1])
    border.discard(0)
    reach = np.isin(lab_img, list(border))
    holes = np.logical_and(free, np.logical_not(reach))
    solid_area = int(solid.sum())
    print(f"{lab}: 实心面积={solid_area}px  内部孔洞={int(holes.sum())}px "
          f"({holes.sum() / max(solid_area, 1) * 100:.2f}% of 实心)")
    if holes.sum() > 50:
        ys, xs = np.nonzero(holes)
        print(f"   孔洞范围 x {xs.min()}..{xs.max()}  y {ys.min()}..{ys.max()}  "
              f"孔洞平均alpha={al[holes].mean():.0f}")
        sizes = ndimage.sum(holes, lab_img, range(1, n + 1))
        big = [int(s) for s in sizes if s > 0]
        print(f"   孔洞连通块数={len(big)}  最大块={max(big) if big else 0}px")
