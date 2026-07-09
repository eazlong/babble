#!/usr/bin/env python3
"""豆包生成视频水印后处理工具。

这个脚本只处理本地视频文件，适合你自己生成并有权编辑的视频素材。
依赖: ffmpeg / ffprobe

常用示例:
  # 豆包常见右下角水印: 模糊遮盖
  python scripts/doubao_watermark.py blur input.mp4

  # 手动指定水印区域: x:y:w:h, 支持 iw/ih 表达式
  python scripts/doubao_watermark.py blur input.mp4 -r "iw-260:ih-96:240:76" -o output.mp4

  # 裁掉底部 88 像素
  python scripts/doubao_watermark.py crop input.mp4 --bottom 88

  # 用自己的图片覆盖右下角
  python scripts/doubao_watermark.py cover input.mp4 --image logo.png

  # 导出首帧, 方便确认水印坐标
  python scripts/doubao_watermark.py preview input.mp4 -o first_frame.jpg
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


DEFAULT_REGION = "iw-260:ih-96:240:76"
DEFAULT_POSITION = "main_w-overlay_w-24:main_h-overlay_h-24"


@dataclass(frozen=True)
class Region:
    x: str
    y: str
    width: str
    height: str


def require_binary(name: str) -> None:
    if shutil.which(name) is None:
        raise SystemExit(f"找不到 {name}。请先安装 FFmpeg 后再运行。")


def run_ffmpeg(cmd: list[str]) -> None:
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"FFmpeg 执行失败，退出码: {exc.returncode}") from exc


def parse_region(value: str) -> Region:
    parts = value.split(":")
    if len(parts) != 4 or any(not part.strip() for part in parts):
        raise argparse.ArgumentTypeError("区域格式必须是 x:y:w:h，例如 iw-260:ih-96:240:76")
    return Region(*(part.strip() for part in parts))


def overlay_expr(expr: str) -> str:
    """Convert crop-style iw/ih expressions to overlay-style main_w/main_h."""
    return expr.replace("iw", "main_w").replace("ih", "main_h")


def default_output(input_path: Path, suffix: str) -> Path:
    return input_path.with_name(f"{input_path.stem}_{suffix}{input_path.suffix}")


def assert_input_file(path: Path) -> None:
    if not path.exists():
        raise SystemExit(f"输入文件不存在: {path}")
    if not path.is_file():
        raise SystemExit(f"输入路径不是文件: {path}")


def video_size(input_path: Path) -> tuple[int, int]:
    require_binary("ffprobe")
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height",
        "-of",
        "json",
        str(input_path),
    ]
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        stream = json.loads(result.stdout)["streams"][0]
        return int(stream["width"]), int(stream["height"])
    except (subprocess.CalledProcessError, KeyError, IndexError, json.JSONDecodeError) as exc:
        raise SystemExit(f"无法读取视频尺寸: {input_path}") from exc


def blur_watermark(input_path: Path, output_path: Path, region: Region, radius: int, power: int) -> None:
    require_binary("ffmpeg")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    filter_complex = (
        f"[0:v]split[base][tmp];"
        f"[tmp]crop={region.width}:{region.height}:{region.x}:{region.y},"
        f"boxblur=luma_radius={radius}:luma_power={power}:"
        f"chroma_radius={radius}:chroma_power={power}[patch];"
        f"[base][patch]overlay={overlay_expr(region.x)}:{overlay_expr(region.y)}[v]"
    )
    run_ffmpeg(
        [
            "ffmpeg",
            "-hide_banner",
            "-i",
            str(input_path),
            "-filter_complex",
            filter_complex,
            "-map",
            "[v]",
            "-map",
            "0:a?",
            "-c:v",
            "libx264",
            "-crf",
            "18",
            "-preset",
            "medium",
            "-c:a",
            "copy",
            "-movflags",
            "+faststart",
            "-y",
            str(output_path),
        ]
    )


def crop_video(input_path: Path, output_path: Path, left: int, top: int, right: int, bottom: int) -> None:
    width, height = video_size(input_path)
    crop_width = width - left - right
    crop_height = height - top - bottom
    if crop_width <= 0 or crop_height <= 0:
        raise SystemExit(f"裁剪参数过大，原始尺寸为 {width}x{height}")

    require_binary("ffmpeg")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    run_ffmpeg(
        [
            "ffmpeg",
            "-hide_banner",
            "-i",
            str(input_path),
            "-vf",
            f"crop={crop_width}:{crop_height}:{left}:{top}",
            "-c:v",
            "libx264",
            "-crf",
            "18",
            "-preset",
            "medium",
            "-c:a",
            "copy",
            "-movflags",
            "+faststart",
            "-y",
            str(output_path),
        ]
    )


def cover_watermark(input_path: Path, output_path: Path, image_path: Path, position: str) -> None:
    assert_input_file(image_path)
    require_binary("ffmpeg")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    run_ffmpeg(
        [
            "ffmpeg",
            "-hide_banner",
            "-i",
            str(input_path),
            "-i",
            str(image_path),
            "-filter_complex",
            f"[0:v][1:v]overlay={position}[v]",
            "-map",
            "[v]",
            "-map",
            "0:a?",
            "-c:v",
            "libx264",
            "-crf",
            "18",
            "-preset",
            "medium",
            "-c:a",
            "copy",
            "-movflags",
            "+faststart",
            "-y",
            str(output_path),
        ]
    )


def preview_frame(input_path: Path, output_path: Path, at_seconds: float) -> None:
    require_binary("ffmpeg")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    run_ffmpeg(
        [
            "ffmpeg",
            "-hide_banner",
            "-ss",
            str(at_seconds),
            "-i",
            str(input_path),
            "-frames:v",
            "1",
            "-update",
            "1",
            "-q:v",
            "2",
            "-y",
            str(output_path),
        ]
    )


def add_common_video_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("input", type=Path, help="输入视频文件")
    parser.add_argument("-o", "--output", type=Path, help="输出文件路径")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="豆包生成视频水印后处理工具")
    subparsers = parser.add_subparsers(dest="command", required=True)

    blur = subparsers.add_parser("blur", help="模糊遮盖水印区域，默认匹配右下角水印")
    add_common_video_arg(blur)
    blur.add_argument(
        "-r",
        "--region",
        type=parse_region,
        default=parse_region(DEFAULT_REGION),
        help=f"水印区域 x:y:w:h，支持 iw/ih 表达式，默认 {DEFAULT_REGION}",
    )
    blur.add_argument("--radius", type=int, default=18, help="模糊半径，默认 18")
    blur.add_argument("--power", type=int, default=3, help="模糊强度，默认 3")

    crop = subparsers.add_parser("crop", help="裁剪画面边缘，适合水印贴边的情况")
    add_common_video_arg(crop)
    crop.add_argument("--left", type=int, default=0, help="裁掉左侧像素")
    crop.add_argument("--top", type=int, default=0, help="裁掉顶部像素")
    crop.add_argument("--right", type=int, default=0, help="裁掉右侧像素")
    crop.add_argument("--bottom", type=int, default=88, help="裁掉底部像素，默认 88")

    cover = subparsers.add_parser("cover", help="用图片覆盖水印")
    add_common_video_arg(cover)
    cover.add_argument("--image", type=Path, required=True, help="覆盖用图片，如 logo.png")
    cover.add_argument("--position", default=DEFAULT_POSITION, help=f"覆盖位置，默认 {DEFAULT_POSITION}")

    preview = subparsers.add_parser("preview", help="导出某一帧，方便确认水印坐标")
    preview.add_argument("input", type=Path, help="输入视频文件")
    preview.add_argument("-o", "--output", type=Path, default=Path("doubao_preview.jpg"), help="输出图片路径")
    preview.add_argument("--at", type=float, default=0.0, help="截图时间，单位秒，默认 0")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    assert_input_file(args.input)

    if args.command == "blur":
        output = args.output or default_output(args.input, "blurred")
        blur_watermark(args.input, output, args.region, args.radius, args.power)
        print(f"完成: {output}")
    elif args.command == "crop":
        output = args.output or default_output(args.input, "cropped")
        crop_video(args.input, output, args.left, args.top, args.right, args.bottom)
        print(f"完成: {output}")
    elif args.command == "cover":
        output = args.output or default_output(args.input, "covered")
        cover_watermark(args.input, output, args.image, args.position)
        print(f"完成: {output}")
    elif args.command == "preview":
        preview_frame(args.input, args.output, args.at)
        print(f"完成: {args.output}")
    else:
        parser.error(f"未知命令: {args.command}")


if __name__ == "__main__":
    main()
