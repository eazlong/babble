"""
图片旋转脚本
用法: python scripts/rotate_image.py <图片路径> <角度> [输出路径]
示例: python scripts/rotate_image.py photo.jpg 90
      python scripts/rotate_image.py photo.jpg 45 output.png
"""
import sys
from pathlib import Path
from PIL import Image


def rotate_image(input_path: str, angle: float, output_path: str = None) -> Path:
    inp = Path(input_path)
    if not inp.exists():
        raise FileNotFoundError(f"图片不存在: {inp}")

    img = Image.open(inp)
    # expand=True 让画布随旋转扩大，避免裁切
    rotated = img.rotate(angle, expand=True)

    if output_path is None:
        stem = inp.stem
        suffix = inp.suffix or ".png"
        output_path = inp.with_name(f"{stem}_rotated_{int(angle)}{suffix}")

    out = Path(output_path)
    # 处理 RGBA → JPEG 不兼容的情况
    if out.suffix.lower() in (".jpg", ".jpeg") and rotated.mode == "RGBA":
        rotated = rotated.convert("RGB")
    rotated.save(out)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    src, deg = sys.argv[1], float(sys.argv[2])
    dst = sys.argv[3] if len(sys.argv) >= 4 else None
    result = rotate_image(src, deg, dst)
    print(f"已保存: {result}")
