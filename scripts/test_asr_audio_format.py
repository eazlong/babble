#!/usr/bin/env python3
"""
测试 ASR 音频数据格式
验证 numpy frombuffer 对不同数据格式的处理
"""

import numpy as np
import struct

# 测试 1: 空数据
print("=" * 60)
print("Test 1: Empty data")
print("=" * 60)
empty_data = b''
print(f"Empty data size: {len(empty_data)}")
try:
    samples = np.frombuffer(empty_data, dtype=np.float32)
    print(f"Success: {len(samples)} samples")
except Exception as e:
    print(f"Error: {e}")

# 测试 2: 有效的 float32 数据（立体声，100 frames）
print("\n" + "=" * 60)
print("Test 2: Valid float32 stereo data (100 frames)")
print("=" * 60)
valid_data = b''
for i in range(100):
    valid_data += struct.pack('ff', 0.1, 0.1)  # 左声道 + 右声道

print(f"Valid data size: {len(valid_data)} bytes")
print(f"Is multiple of 4: {len(valid_data) % 4 == 0}")
try:
    samples = np.frombuffer(valid_data, dtype=np.float32)
    print(f"Success: {len(samples)} samples")
    print(f"Expected: {100 * 2} samples (100 frames * 2 channels)")
except Exception as e:
    print(f"Error: {e}")

# 测试 3: 奇数长度数据（模拟格式错误）
print("\n" + "=" * 60)
print("Test 3: Odd-length data (simulating format error)")
print("=" * 60)
odd_data = valid_data + b'\x00'  # 添加 1 byte
print(f"Odd data size: {len(odd_data)} bytes")
print(f"Is multiple of 4: {len(odd_data) % 4 == 0}")
try:
    samples = np.frombuffer(odd_data, dtype=np.float32)
    print(f"Success: {len(samples)} samples")
except Exception as e:
    print(f"Error: {e}")

# 测试 4: 非常小的数据（模拟短音频）
print("\n" + "=" * 60)
print("Test 4: Small valid data (1 frame)")
print("=" * 60)
small_data = struct.pack('ff', 0.1, 0.1)  # 1 frame = 8 bytes
print(f"Small data size: {len(small_data)} bytes")
print(f"Is multiple of 4: {len(small_data) % 4 == 0}")
try:
    samples = np.frombuffer(small_data, dtype=np.float32)
    print(f"Success: {len(samples)} samples")
except Exception as e:
    print(f"Error: {e}")

print("\n" + "=" * 60)
print("Conclusion:")
print("=" * 60)
print("✅ Valid float32 data must be multiple of 4 bytes")
print("❌ Empty data (0 bytes) causes error")
print("❌ Odd-length data causes 'buffer size must be a multiple of element size' error")