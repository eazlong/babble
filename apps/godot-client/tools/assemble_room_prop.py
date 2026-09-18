"""BeginningFP 主人房道具装配：把抠好的家具按"旧素材基准尺寸"原位放入画布，
并确定性地添加 接触影 与（可选）苏醒态魔法光。

为什么不用生成图直接缩放：
- 生成图的主体纵横比与旧素材不同，直接铺满画布会导致家具比例突变、
  甚至在状态切换时轮廓跳变；
- 接触影必须"落在房间地板上"才不悬浮，而 prompt 里要它不画影（否则抠图会
  把影当主体保留），所以影由 Pillow 确定性添加；
- 苏醒态由闭合态派生（同一剪影 + 内部发光），保证 closed→awake 原地切换不跳。

用法：
  python tools/assemble_room_prop.py --cut <抠好的png> --canvas 420x520 \
      --subject-height 499 --bottom-margin 11 --shadow --out out.png
  python tools/assemble_room_prop.py --cut <抠好的png> --canvas 420x520 \
      --subject-height 499 --bottom-margin 11 --shadow --awake-glow --out out_awake.png
"""

import argparse
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage


def extract_subject(im):
    a = np.asarray(im)[:, :, 3]
    ys, xs = np.nonzero(a > 16)
    if len(ys) == 0:
        raise SystemExit("cut image is fully transparent")
    return im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def contact_shadow(canvas_size, cx, base_y, obj_w, obj_h, strength=1.0):
    """软接触影：扁平椭圆 + 轻模糊，向右偏移（房间主光来自左侧）。

    高度刻意压得很扁：画布是固定尺寸（420x520 / 360x460），物体底部只留 9-11px，
    影一旦超出画布就会被裁出硬边（在地板上表现为一条直线）。
    """
    w, h = canvas_size
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    # 影必须比物体**更宽**才能从两侧露出来：只画在物体轮廓内的影会被物体整块盖住，
    # 等于没画（实测底边线附近像素变化 = 0.0）。
    sw = int(min(obj_w * 1.22, w - 2))
    sh_h = max(6, min(11, int(obj_h * 0.022)))
    ox = int(obj_w * 0.04)  # 光从左来 → 影偏右
    cy = base_y - 1
    left = cx - sw // 2 + ox
    top = cy - sh_h // 2
    d.ellipse([left, top, left + sw, top + sh_h], fill=(58, 40, 26, int(150 * strength)))
    sh = sh.filter(ImageFilter.GaussianBlur(max(2.5, sh_h * 0.4)))
    # 影若在画布边缘被切断，贴进房间后会在地板上留一条直线硬边 → 距边 8px 内渐隐到 0
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rectangle([8, 8, w - 9, h - 9], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(5))
    a = sh.getchannel("A").point(lambda v: v)
    sh.putalpha(Image.composite(a, Image.new("L", (w, h), 0), m))
    return sh


def edge_shade(img, strength=0.08, height=7):
    """沿物体内缘做轻微压暗，把"贴上去"的亮轮廓高光焊进背景。

    生成图常自带一圈轮廓高光（rim light），抠出来后贴到浅色墙上会读成"白描边残留"，
    而这不是抠图残边（decontaminate_alpha 已把边缘 RGB 吸附到最近不透明色）。
    做法：按"到透明区的距离"在物体内侧前 height 像素内做梯度乘暗。
    """
    a = np.array(img).astype(np.float32)
    al = a[:, :, 3]
    if not (al < 128).any():
        return img
    dist = ndimage.distance_transform_edt(al >= 128)
    t = np.clip(1.0 - dist / max(1.0, height), 0.0, 1.0)
    f = 1.0 - strength * (t ** 1.2)
    f = np.where(al > 8, f, 1.0)[:, :, None]
    a[:, :, :3] *= f
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def edge_neutral(img, desat=0.6, darken=0.10, band=3.0):
    """清除边缘的颜色偏色（青/蓝 rim），保留抗锯齿。

    为什么需要：decontaminate_alpha 把边缘 RGB 替换成"最近不透明像素"的颜色，
    而最近像素常是蓝书脊、青绿角饰或冷色暗部 → 轮廓上出现一圈青蓝 rim，
    贴到暖色墙上就是视觉反复指出的"贴图感/青绿描边"。实测边缘 ΔB-ΔR 达 +8。
    做法：边缘带内向外梯度地把颜色拉向自身亮度（并略加暖），再轻微压暗。
    """
    a = np.array(img).astype(np.float32)
    al = a[:, :, 3]
    if not (al < 128).any():
        return img
    dist = ndimage.distance_transform_edt(al >= 128)
    t = np.clip(1.0 - dist / band, 0.0, 1.0) ** 0.8          # 最外缘=1
    lum = (0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2])
    neutral = np.dstack([lum * 1.03, lum * 1.0, lum * 0.94])  # 略暖，抵消冷偏
    k = np.where(al > 8, t * desat, 0.0)[:, :, None]
    a[:, :, :3] = a[:, :, :3] * (1.0 - k) + neutral * k
    a[:, :, :3] *= (1.0 - darken * np.where(al > 8, t, 0.0))[:, :, None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def warm_teal(img, strength=0.75):
    """把偏青（G、B 明显高于 R）的像素拉回暖木色系。

    设计里保留了旧素材的"青绿角饰"，但生成图把它画得偏青偏亮，
    在轮廓上就变成视觉反复指出的"浅青色描边"，与暖木房间冲突。
    只对有青偏的像素做色相迁移，木色/奶油色像素不受影响。
    """
    a = np.array(img).astype(np.float32)
    al = a[:, :, 3]
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    teal = np.clip(((g - r) + (b - r)) / 60.0, 0.0, 1.0)          # 青偏程度 0..1
    k = np.where(al > 8, teal * strength, 0.0)[:, :, None]
    lum = (0.299 * r + 0.587 * g + 0.114 * b)
    warm = np.dstack([lum * 1.10, lum * 0.99, lum * 0.84])         # 暖木/橄榄方向
    a[:, :, :3] = a[:, :, :3] * (1.0 - k) + warm * k
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def add_grain(img, amp=6.0, scale=1.1, seed=3):
    """给物料表面加细颗粒肌理，模拟厚涂的布纹/笔触。

    房间底图有可见的笔触与颗粒，而生成的道具表面过于干净平滑，
    贴上去就被读成"平涂/净边、像贴图"。这里只加很轻的亮度噪声（±6 级）。
    """
    a = np.array(img).astype(np.float32)
    al = a[:, :, 3]
    h, w = al.shape
    rng = np.random.default_rng(seed)
    n = rng.normal(0.0, 1.0, (h, w))
    if scale > 1:
        n = ndimage.gaussian_filter(n, scale)
    peak = float(np.abs(n).max()) + 1e-6
    k = np.where(al > 8, 1.0, 0.0)
    a[:, :, :3] += (n / peak * amp * k)[:, :, None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def feather_alpha(img, radius=0.8):
    """轻微柔化剪影，避免"刀刃般干净"的抠图边缘与厚涂房间脱节。"""
    a = np.array(img).astype(np.float32)
    a[:, :, 3] = np.clip(ndimage.gaussian_filter(a[:, :, 3], radius), 0, 255)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def cap_highlights(img, cap=238, desat=0.25):
    """把物料的最高光压进房间色域——**染色成暖色，而不是去饱和**。

    实测：书柜奶油包边达 (255,247,164)；而房间墙色是高饱和暖黄 (230,210,160)。
    把包边去饱和成中性 (229,229,222) 后，它在暖色旁**因同时对比反而显冷**，
    视觉仍读成"浅青色描边"（青偏像素已 0.0% 却仍被这样描述）。
    所以这里把过亮像素往暖色（木色受暖光的合理高光）迁移，并轻微压暗。
    """
    a = np.array(img).astype(np.float32)
    al = a[:, :, 3]
    lum = 0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]
    over = np.clip((lum - cap) / max(1.0, 255.0 - cap), 0.0, 1.0)
    k = np.where(al > 8, over, 0.0)[:, :, None]
    warm = np.dstack([lum * 1.06, lum * 0.97, lum * 0.80])   # 暖木高光，贴住房间色温
    a[:, :, :3] = a[:, :, :3] * (1 - k) + warm * k
    a[:, :, :3] *= (1 - k * 0.06)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def remove_brass(img, keep_box=None):
    """抹掉生成图里残留的黄铜件，只保留我们自己画的那一处。

    为什么需要：即使 prompt 写"全图没有任何金属"，模型仍会在右侧门缘补一片铜件
    （"每扇门一片"的先验太强）。

    判据演进（重要教训，试错三轮）：
    ① 用 R-B / G-B 都分不开：受光暖木的 G-B 90 分位已达 73（黄铜才 ~78），
       用 G-B>55 会圈进 59000px、把受光木面一起重涂成糊斑。
    ② **色相才是可靠判据**：黄铜 hue 40–46°、val>0.7；红木 hue 16°、val 0.43
       —— 分离度极大。再叠"紧凑块"过滤（面积 40–2500px、最长边<90px、长宽比<6）
       以排除门缝的竖直亮条（12x152、2x198 这类受光边，长宽比>10）。
    实测：A（门缝中央）与 B（右框背光侧，更暗故 G-B 判据会漏）两处铜件都捕获，共 505px。
    """
    a = np.array(img).astype(np.float32)
    r, g, b, al = a[:, :, 0] / 255, a[:, :, 1] / 255, a[:, :, 2] / 255, a[:, :, 3]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    d = mx - mn + 1e-6
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    # 黄铜 hue 40-46°、sat~0.70、val~0.73；红木 hue 16°、val 0.43；受光边 val>0.92
    # 注意：本函数跑在**已缩放到显示尺寸**的图上（如 443 高），铜块随之缩小，
    # 阈值必须按显示尺度给（曾在原始 983 高上设 size>=40，缩放后全被滤掉只剩 505px）。
    cand = (hue > 33) & (hue < 55) & (sat > 0.6) & (mx > 0.55) & (mx < 0.92) & (al > 8)
    if keep_box is not None:
        x0, y0, x1, y1 = keep_box
        cand[y0:y1, x0:x1] = False
    lab, n = ndimage.label(cand)
    brass = np.zeros_like(cand)
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        if not len(ys) or not (12 <= len(ys) <= 3000):
            continue
        bh, bw = ys.max() - ys.min() + 1, xs.max() - xs.min() + 1
        if max(bh, bw) < 130 and max(bh, bw) / max(1, min(bh, bw)) < 8.0:
            brass[ys, xs] = True
    if not brass.any():
        print("  remove_brass: 未发现残留铜件")
        return img
    src = ~brass
    idx = ndimage.distance_transform_edt(brass, return_distances=False, return_indices=True)
    take = brass & src[idx[0], idx[1]]
    a[:, :, :3][take] = a[:, :, :3][idx[0][take], idx[1][take]]
    print(f"  remove_brass: 抹除残留铜件 {int(take.sum())}px（候选 {int(cand.sum())}px）")
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def draw_brass_lock(img, fx=0.5, fy=0.52, width_frac=0.072):
    """在门缝处确定性地画一片中式黄铜面叶 + 吊环。

    为什么由 Pillow 画而不是生成：图像模型**做不到"全图只有一处金属"**——
    同一 prompt 三次分别给出 4 片锁牌、8 颗铜钉、2 处铜件（都是"每扇门一片"的
    先验）。精确数量属于符号化任务，必须自己画（同技能里"精确数量几何用 Pillow"）。
    做法：闭合时双门缝就在物体水平中央，所以按主体宽度的百分比定位即可；
    面叶为竖长圆角矩形（上亮下暗的金属渐变 + 投影），下挂一个圆环。
    """
    a = np.array(img)
    ys, xs = np.nonzero(a[:, :, 3] > 16)
    if not len(ys):
        return img
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    bw = x1 - x0 + 1
    cx = int(x0 + fx * bw)
    cy = int(y0 + fy * (y1 - y0))
    w = max(7, int(bw * width_frac))
    h = int(w * 1.7)

    ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    # 投影：贴在门板上的一点暗部
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [cx - w // 2 - 2, cy - h // 2 + 2, cx + w // 2 + 2, cy + h // 2 + 8],
        radius=max(2, w // 3), fill=(58, 36, 14, 130))
    ov = Image.alpha_composite(ov, sh.filter(ImageFilter.GaussianBlur(max(1.2, w * 0.16))))
    # 面叶：竖向圆角矩形 + 上亮下暗
    bx0, by0, bx1, by1 = cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2
    d = ImageDraw.Draw(ov)
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=max(2, w // 3), fill=(188, 146, 68, 255))
    plate = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dp = ImageDraw.Draw(plate)
    for i, t in enumerate([(0.0, 0.45, (226, 190, 116, 255)), (0.45, 0.72, (200, 158, 78, 255)), (0.72, 1.0, (146, 108, 46, 255))]):
        y_a = int(by0 + (by1 - by0) * t[0]); y_b = int(by0 + (by1 - by0) * t[1])
        dp.rectangle([bx0 + 1, y_a, bx1 - 1, y_b], fill=t[2])
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([bx0, by0, bx1, by1], radius=max(2, w // 3), fill=255)
    ov = Image.composite(plate, ov, mask)
    # 吊环
    rd = int(w * 0.62)
    rx, ry = cx, by1 + int(rd * 0.75)
    d = ImageDraw.Draw(ov)
    d.ellipse([rx - rd // 2, ry - rd // 2, rx + rd // 2, ry + rd // 2],
              outline=(196, 152, 74, 255), width=max(2, w // 4))
    d.ellipse([rx - rd // 6, ry - rd // 6, rx + rd // 6, ry + rd // 6],
              fill=(150, 112, 48, 255))
    # 高光
    hl = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dhl = ImageDraw.Draw(hl)
    dhl.line([bx0 + 2, by0 + 3, bx1 - 2, by0 + 3], fill=(246, 226, 176, 170), width=1)
    dhl.rectangle([bx0 + 1, by0 + 2, bx0 + max(1, w // 6), by1 - 1], fill=(238, 210, 150, 70))   # 左侧竖高光
    dhl.rectangle([bx1 - max(1, w // 7), by0 + 2, bx1 - 1, by1 - 1], fill=(96, 68, 26, 80))      # 右侧压暗
    ov = Image.alpha_composite(ov, hl.filter(ImageFilter.GaussianBlur(0.5)))
    # 锁孔（面叶下三分之一处）：小圆 + 竖槽，做成深色凹陷
    kh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dkh = ImageDraw.Draw(kh)
    kcy = cy + int(h * 0.17)
    kr = max(2, w // 7)
    dkh.ellipse([cx - kr, kcy - kr, cx + kr, kcy + kr], fill=(74, 52, 22, 235))
    dkh.rectangle([cx - max(1, kr // 3), kcy, cx + max(1, kr // 3), kcy + int(h * 0.13)], fill=(74, 52, 22, 235))
    dkh.ellipse([cx - kr + 1, kcy - kr + 1, cx + kr - 1, kcy + kr - 1], outline=(214, 178, 104, 150), width=1)
    ov = Image.alpha_composite(ov, kh.filter(ImageFilter.GaussianBlur(0.4)))
    # 只贴在物体不透明范围内，避免溢到轮廓外
    keep = Image.new("L", img.size, 0)
    keep.paste(img.convert("RGBA").split()[3], (0, 0))
    ov.putalpha(Image.composite(ov.split()[3], Image.new("L", img.size, 0), keep))
    return Image.alpha_composite(img.convert("RGBA"), ov)


def contact_ao(img, base_y, strength=0.34, height=10):
    """在物体**自身底部**做接触暗化（AO）：底边向上 height 像素按梯度乘暗。

    为什么需要：衣橱画布 360px 宽而物料主体 338px 宽，两侧只剩 11px，
    地板影椭圆被裁到只剩低 alpha 边缘 → 引擎里实测暗化仅 +0.5（等于没有）。
    当画布没有放影的空间时，落地感只能由物体自身的底部暗化表达。
    """
    a = np.array(img).astype(np.float32)
    y0 = max(0, base_y - height)
    for y in range(y0, base_y):
        t = (y - y0) / max(1, base_y - y0)          # 0=上部 1=底边
        f = 1.0 - strength * (t ** 1.6)
        a[y, :, :3] *= f                            # 只压 RGB，alpha 不变
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def awake_glow(img):
    """苏醒态：暗部发光（青白）+ 外发光 + 少量光点。剪影完全不变。"""
    arr = np.asarray(img).astype(np.float32)
    rgb, a = arr[:, :, :3], arr[:, :, 3]
    lum = (0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]) / 255.0
    body = (a > 32).astype(np.float32)
    # 暗部（柜内、门缝）发光最强
    glow = np.clip(1.0 - lum, 0.0, 1.0) ** 1.6 * body
    glow_img = Image.fromarray((glow * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(3))
    g = np.asarray(glow_img).astype(np.float32) / 255.0
    tint = np.array([186.0, 246.0, 238.0])  # 青白
    add = g[:, :, None] * tint[None, None, :] * 0.75
    rgb = np.clip(rgb + add, 0, 255)
    # 外发光（剪影外一圈柔和青白）
    halo = Image.fromarray((body * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(14))
    hn = np.asarray(halo).astype(np.float32) / 255.0
    hn = np.clip(hn - body, 0, 1)
    rgb = np.clip(rgb + hn[:, :, None] * tint[None, None, :] * 0.35, 0, 255)
    out = np.dstack([rgb, a]).astype(np.uint8)
    im = Image.fromarray(out, "RGBA")
    # 少量光点
    d = ImageDraw.Draw(im)
    smalls = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(smalls)
    ys, xs = np.nonzero(a > 32)
    rng = np.random.default_rng(7)
    for _ in range(14):
        px = int(rng.integers(xs.min(), xs.max()))
        py = int(rng.integers(ys.min() + (ys.max() - ys.min()) // 5, ys.max()))
        r = int(rng.integers(2, 5))
        ds.ellipse([px - r, py - r, px + r, py + r], fill=(214, 252, 246, 190))
    smalls = smalls.filter(ImageFilter.GaussianBlur(1.2))
    return Image.alpha_composite(im, smalls)


def main():
    ap = argparse.ArgumentParser(description="Assemble a room prop cutout onto its canvas with contact shadow")
    ap.add_argument("--cut", required=True, help="cut-out RGBA png")
    ap.add_argument("--canvas", required=True, help="WxH e.g. 420x520")
    ap.add_argument("--subject-height", type=int, required=True, help="target subject height in px (match the old asset)")
    ap.add_argument("--bottom-margin", type=int, default=11, help="px between subject bottom and canvas bottom")
    ap.add_argument("--shadow", action="store_true", help="bake a deterministic soft contact shadow")
    ap.add_argument("--shadow-strength", type=float, default=1.0)
    ap.add_argument("--awake-glow", action="store_true", help="derive the awakened state (same silhouette + glow)")
    ap.add_argument("--contact-ao", action="store_true", help="darken the subject's own bottom rows (grounding when the canvas leaves no room for a floor shadow)")
    ap.add_argument("--ao-strength", type=float, default=0.34)
    ap.add_argument("--edge-shade", action="store_true", help="gently darken the subject's inner rim to blend it into the wall")
    ap.add_argument("--edge-neutral", action="store_true", help="neutralise the cold/teal colour bias along the rim")
    ap.add_argument("--cap-highlights", action="store_true", help="bring the prop's brightest trim into the room's tonal range")
    ap.add_argument("--cap-value", type=float, default=238.0, help="luminance above which highlights are compressed")
    ap.add_argument("--shade-strength", type=float, default=0.08)
    ap.add_argument("--warm-teal", action="store_true", help="migrate cyan-biased pixels toward warm wood (keeps magic glow states untouched)")
    ap.add_argument("--brass-lock", action="store_true", help="draw ONE Chinese brass face-plate + ring on the door seam (AIGC cannot hold an exact hardware count)")
    ap.add_argument("--lock-pos", default="0.5,0.52", help="lock position as fractions of the subject bbox (fx,fy)")
    ap.add_argument("--grain", action="store_true", help="add fine painterly grain so the surface matches the room texture")
    ap.add_argument("--feather", type=float, default=0.0, help="alpha feather radius in px")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    cw, ch = (int(v) for v in args.canvas.lower().split("x"))
    sub = extract_subject(Image.open(args.cut).convert("RGBA"))
    sc = args.subject_height / sub.height
    sub = sub.resize((max(1, round(sub.width * sc)), args.subject_height), Image.LANCZOS)
    if args.warm_teal:
        sub = warm_teal(sub)
    if args.brass_lock:
        sub = remove_brass(sub)          # 先抹掉模型自己加的铜件
        _fx, _fy = (float(v) for v in args.lock_pos.split(","))
        sub = draw_brass_lock(sub, fx=_fx, fy=_fy)
    if args.cap_highlights:
        sub = cap_highlights(sub, cap=args.cap_value)
    if args.edge_neutral:
        sub = edge_neutral(sub)
    if args.edge_shade:
        sub = edge_shade(sub, strength=args.shade_strength)
    if args.grain:
        sub = add_grain(sub)
    if args.contact_ao:
        sub = contact_ao(sub, sub.height, strength=args.ao_strength)
    if args.feather > 0:
        sub = feather_alpha(sub, args.feather)

    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    x = (cw - sub.width) // 2
    y = ch - args.bottom_margin - sub.height

    if args.shadow:
        canvas = Image.alpha_composite(
            canvas, contact_shadow((cw, ch), x + sub.width // 2, y + sub.height, sub.width, sub.height, args.shadow_strength)
        )
    canvas.paste(sub, (x, y), sub)
    if args.awake_glow:
        canvas = awake_glow(canvas)
    canvas.save(args.out)
    print(f"assembled {args.out}  canvas={cw}x{ch} subject={sub.width}x{sub.height} at ({x},{y})"
          f" shadow={args.shadow} awake={args.awake_glow}")


if __name__ == "__main__":
    sys.exit(main())
