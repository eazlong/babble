#!/usr/bin/env python3
"""
讯飞语音服务手动测试脚本
用于验证讯飞TTS和ASR集成是否正常工作
"""

import asyncio
import os
import sys
import base64
import time

# 确保环境变量已加载
from dotenv import load_dotenv
load_dotenv()

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from src.services.xfyun_tts import xfyun_tts_service
from src.services.xfyun_asr import xfyun_asr_service
from src.services.service_manager import service_manager


async def test_tts():
    """测试讯飞TTS"""
    print("=" * 60)
    print("Testing Xfyun TTS (Text-to-Speech)")
    print("=" * 60)

    # 初始化服务
    await xfyun_tts_service.init()

    if not xfyun_tts_service.is_available:
        print("❌ Xfyun TTS not available (missing credentials)")
        return

    test_texts = [
        "Hello children! Welcome to LinguaQuest.",
        "欢迎来到LinguaQuest，小朋友们！",
        "Can you say apple?",
        "今天我们来学习英语单词。",
    ]

    for i, text in enumerate(test_texts):
        print(f"\n[{i+1}] Testing: '{text}'")
        try:
            start_time = time.time()
            result = await xfyun_tts_service.synthesize(text, "spirit", "cn_en")
            elapsed = time.time() - start_time

            print(f"  ✅ Success!")
            print(f"  - Audio size: {len(result.audio_data)} chars (base64)")
            print(f"  - Format: {result.format}")
            print(f"  - Duration: {result.duration_ms}ms")
            print(f"  - Latency: {elapsed:.2f}s")

            # 保存为文件验证
            output_file = f"/tmp/xfyun_tts_test_{i+1}.mp3"
            with open(output_file, "wb") as f:
                f.write(base64.b64decode(result.audio_data))
            print(f"  - Saved to: {output_file}")

        except Exception as e:
            print(f"  ❌ Failed: {e}")

    print("\n" + "=" * 60)


async def test_asr():
    """测试讯飞ASR（需要准备测试音频）"""
    print("=" * 60)
    print("Testing Xfyun ASR (Automatic Speech Recognition)")
    print("=" * 60)

    # 初始化服务
    await xfyun_asr_service.init()

    if not xfyun_asr_service.is_available:
        print("❌ Xfyun ASR not available (missing credentials)")
        return

    # 从文件加载测试音频（需要用户准备）
    test_file = "/tmp/test_audio.raw"

    if os.path.exists(test_file):
        print(f"\n[1] Testing with file: {test_file}")
        with open(test_file, "rb") as f:
            audio_bytes = f.read()

        print(f"  - Audio size: {len(audio_bytes)} bytes")
        try:
            start_time = time.time()
            result = await xfyun_asr_service.transcribe(audio_bytes, "cn_en")
            elapsed = time.time() - start_time

            print(f"  ✅ Success!")
            print(f"  - Text: {result.text}")
            print(f"  - Confidence: {result.confidence}")
            print(f"  - Language: {result.language}")
            print(f"  - Latency: {elapsed:.2f}s")

        except Exception as e:
            print(f"  ❌ Failed: {e}")
    else:
        print(f"\n⚠️  Test file not found: {test_file}")
        print("   To test ASR, prepare a PCM audio file:")
        print("   - Format: float32 stereo 44100Hz (Godot format)")
        print("   - Or: int16 mono 16000Hz (standard format)")
        print("   - Save to: /tmp/test_audio.raw")

    print("\n" + "=" * 60)


async def test_service_manager():
    """测试ServiceManager（完整集成）"""
    print("=" * 60)
    print("Testing ServiceManager (Full Integration)")
    print("=" * 60)

    # 初始化所有服务
    await service_manager.init_all()

    print(f"\nService Mode: {service_manager.mode.value}")
    print(f"ASR Chain: {[e.value for e in service_manager._asr_chain]}")
    print(f"TTS Chain: {[e.value for e in service_manager._tts_chain]}")

    # 测试TTS通过ServiceManager
    print(f"\n[1] Testing TTS via ServiceManager")
    test_text = "Hello, this is a test via ServiceManager"

    try:
        start_time = time.time()
        audio_data, format_type = await service_manager.synthesize(test_text, "spirit", "en")
        elapsed = time.time() - start_time

        print(f"  ✅ Success!")
        print(f"  - Audio size: {len(audio_data)} chars (base64)")
        print(f"  - Format: {format_type}")
        print(f"  - Latency: {elapsed:.2f}s")

        # 保存文件
        output_file = f"/tmp/service_manager_tts_test.mp3"
        with open(output_file, "wb") as f:
            f.write(base64.b64decode(audio_data))
        print(f"  - Saved to: {output_file}")

    except Exception as e:
        print(f"  ❌ Failed: {e}")

    # 测试ASR（如果有音频文件）
    test_audio_file = "/tmp/test_audio.raw"
    if os.path.exists(test_audio_file):
        print(f"\n[2] Testing ASR via ServiceManager")
        with open(test_audio_file, "rb") as f:
            audio_bytes = f.read()

        try:
            start_time = time.time()
            result = await service_manager.transcribe(audio_bytes, "cn_en")
            elapsed = time.time() - start_time

            print(f"  ✅ Success!")
            print(f"  - Text: {result.text}")
            print(f"  - Confidence: {result.confidence}")
            print(f"  - Language: {result.language}")
            print(f"  - Latency: {elapsed:.2f}s")

        except Exception as e:
            print(f"  ❌ Failed: {e}")

    print("\n" + "=" * 60)


async def test_mode_switching():
    """测试模式切换"""
    print("=" * 60)
    print("Testing Mode Switching")
    print("=" * 60)

    # 测试环境
    original_mode = os.environ.get("VOICE_SERVICE_MODE", "production")

    print(f"\nCurrent mode: {original_mode}")

    # 切换到test模式
    os.environ["VOICE_SERVICE_MODE"] = "test"
    print(f"\n[1] Switching to TEST mode")

    from src.services.service_manager import ServiceManager
    test_manager = ServiceManager()
    print(f"  - Mode: {test_manager.mode.value}")
    print(f"  - ASR chain: {[e.value for e in test_manager._asr_chain]}")
    print(f"  - TTS chain: {[e.value for e in test_manager._tts_chain]}")
    assert test_manager.mode.value == "test"
    assert test_manager._asr_chain[0].value == "xfyun"

    # 切换到production模式
    os.environ["VOICE_SERVICE_MODE"] = "production"
    print(f"\n[2] Switching to PRODUCTION mode")

    prod_manager = ServiceManager()
    print(f"  - Mode: {prod_manager.mode.value}")
    print(f"  - ASR chain: {[e.value for e in prod_manager._asr_chain]}")
    print(f"  - TTS chain: {[e.value for e in prod_manager._tts_chain]}")
    assert prod_manager.mode.value == "production"
    assert prod_manager._asr_chain[0].value == "whisper"

    # 恢复原模式
    os.environ["VOICE_SERVICE_MODE"] = original_mode

    print("\n✅ Mode switching works correctly")
    print("=" * 60)


async def main():
    """主测试函数"""
    # 检查环境变量
    required_vars = ["XFYUN_APP_ID", "XFYUN_API_KEY", "XFYUN_API_SECRET"]
    missing = [v for v in required_vars if not os.environ.get(v)]

    if missing:
        print("=" * 60)
        print("❌ Error: Missing environment variables")
        print("=" * 60)
        print(f"Missing: {missing}")
        print("\nPlease configure in .env file:")
        print("  XFYUN_APP_ID=<your-app-id>")
        print("  XFYUN_API_KEY=<your-api-key>")
        print("  XFYUN_API_SECRET=<your-api-secret>")
        print("\nGet credentials from: https://www.xfyun.cn/")
        sys.exit(1)

    # 运行测试
    await test_tts()
    await test_asr()
    await test_service_manager()
    await test_mode_switching()

    print("=" * 60)
    print("✅ All tests completed!")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Check generated audio files in /tmp/")
    print("2. Integrate with Godot client for full testing")
    print("3. Test fallback by disabling Xfyun credentials")


if __name__ == "__main__":
    asyncio.run(main())