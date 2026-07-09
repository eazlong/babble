#!/usr/bin/env python3
"""
从视频中按固定时间间隔提取帧截图（包含首尾帧）
用法: python extract_frames.py <视频文件> <输出目录> [间隔毫秒数]
示例: python extract_frames.py video.mp4 ./screenshots 5000
"""
import sys
import subprocess
import json
from pathlib import Path

def get_video_duration(video_path):
    """获取视频时长（毫秒）"""
    cmd = [
        'ffprobe',
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        video_path
    ]

    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        data = json.loads(result.stdout)
        duration = float(data['format']['duration'])
        return int(duration * 1000)
    except (subprocess.CalledProcessError, KeyError, json.JSONDecodeError) as e:
        print(f"✗ 错误: 无法获取视频时长")
        sys.exit(1)

def extract_frames(video_path, output_dir, interval_ms=5000):
    """
    从视频文件中按固定间隔提取帧（包含首尾帧）

    Args:
        video_path: 视频文件路径
        output_dir: 输出目录
        interval_ms: 截图间隔毫秒数，默认5000ms（5秒）
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)

    # 获取视频总时长
    duration_ms = get_video_duration(video_path)
    print(f"✓ 视频时长: {duration_ms}ms ({duration_ms/1000:.2f}秒)")

    # 生成时间点列表（包含首尾）
    timestamps = []
    current = 0

    while current < duration_ms:
        timestamps.append(current)
        current += interval_ms

    # 确保包含最后一帧
    if timestamps[-1] != duration_ms:
        timestamps.append(duration_ms)

    print(f"✓ 将提取 {len(timestamps)} 个时间点")

    # 逐个时间点截图
    for i, ts in enumerate(timestamps, 1):
        output_file = output_dir / f'frame_{i:04d}.jpg'

        cmd = [
            'ffmpeg',
            '-ss', str(ts / 1000.0),  # 转换为秒
            '-i', video_path,
            '-vframes', '1',
            '-q:v', '2',
            '-y',  # 覆盖已有文件
            str(output_file)
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            print(f"  [{i}/{len(timestamps)}] {ts}ms → {output_file.name}")
        except subprocess.CalledProcessError as e:
            print(f"  ✗ 时间点 {ts}ms 截图失败")

    print(f"✓ 截图完成，保存到 {output_dir}")
    print(f"✓ 共生成 {len(timestamps)} 张截图")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    video = sys.argv[1]
    output = sys.argv[2]
    interval_ms = int(sys.argv[3]) if len(sys.argv) > 3 else 5000

    if not Path(video).exists():
        print(f"✗ 错误: 视频文件不存在: {video}")
        sys.exit(1)

    extract_frames(video, output, interval_ms)
