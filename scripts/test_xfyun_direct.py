#!/usr/bin/env python3
"""Test Xfyun TTS API directly"""

import hashlib
import base64
import json
import time
import requests

# Credentials from voice-service container
APP_ID = "5acdb572"
API_KEY = "bb01481f1e5e2db4478d571fe377f17b"
API_SECRET = "317f41735d08dc84f7872a5b7371f981"

API_URL = "https://tts-api.xfyun.cn/v2/tts"

def build_request_body(text: str) -> dict:
    return {
        "common": {"app_id": APP_ID},
        "business": {
            "auf": "audio/L16;rate=16000",
            "aue": "lame",
            "speed": 40,
            "volume": 60,
            "pitch": 55,
            "voice_name": "xiaoyan",
            "reg": 2,
            "rdn": 0,
        },
        "data": {"text": text, "status": 2},
    }

def build_headers(request_body: dict) -> dict:
    cur_time = str(int(time.time()))

    business_str = json.dumps(request_body.get("business", {}), separators=(",", ":"))
    param_base64 = base64.b64encode(business_str.encode("utf-8")).decode("utf-8")

    check_sum_src = f"{API_KEY}{cur_time}{param_base64}"
    check_sum = hashlib.md5(check_sum_src.encode("utf-8")).hexdigest()

    return {
        "Content-Type": "application/json",
        "X-Appid": APP_ID,
        "X-CurTime": cur_time,
        "X-Param": param_base64,
        "X-CheckSum": check_sum,
    }

def test_xfyun_tts():
    text = "你好世界"
    request_body = build_request_body(text)
    headers = build_headers(request_body)

    print(f"Testing Xfyun TTS API...")
    print(f"App ID: {APP_ID}")
    print(f"Text: {text}")
    print(f"Headers: {headers}")

    try:
        response = requests.post(API_URL, headers=headers, json=request_body, timeout=30.0)
        print(f"\nStatus code: {response.status_code}")
        print(f"Response: {response.text[:500]}")

        if response.status_code == 200:
            result = response.json()
            if result.get("code") == 0:
                audio_base64 = result.get("data", {}).get("audio", "")
                print(f"✅ Success! Audio data length: {len(audio_base64)} chars")
                return True
            else:
                print(f"❌ API error: code={result.get('code')}, message={result.get('message')}")
                return False
        else:
            print(f"❌ HTTP error: {response.status_code}")
            print(f"Response body: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Exception: {e}")
        return False

if __name__ == "__main__":
    success = test_xfyun_tts()
    if success:
        print("\n✅ Xfyun TTS API is working!")
    else:
        print("\n❌ Xfyun TTS API failed - need to check credentials/quota")