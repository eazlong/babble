#!/usr/bin/env python3
"""
讯飞 TTS API 验证脚本
用于检查讯飞 TTS 服务是否可用

使用方法：
1. 登录讯飞控制台 https://www.xfyun.cn/
2. 检查应用 APP_ID=5acdb572 是否开通了"在线语音合成"服务
3. 检查配额是否充足
"""

import requests
import hashlib
import base64
import json
import time
import sys

# 从 voice-service 容器获取的凭证
APP_ID = "5acdb572"
API_KEY = "bb01481f1e5e2db4478d571fe377f17b"
API_SECRET = "317f41735d08dc84f7872a5b7371f981"

API_URL = "https://tts-api.xfyun.cn/v2/tts"

def test_with_correct_params():
    """使用正确格式测试讯飞 TTS API"""

    text = "你好世界"

    # 构建请求体（按照讯飞官方文档）
    request_body = {
        "common": {"app_id": APP_ID},
        "business": {
            "auf": "audio/L16;rate=16000",
            "aue": "lame",  # MP3 格式
            "speed": 50,
            "volume": 50,
            "pitch": 50,
            "voice_name": "xiaoyan",
            "reg": 2,
            "rdn": 0,
        },
        "data": {"text": text, "status": 2},
    }

    # 构建请求头
    cur_time = str(int(time.time()))
    business_str = json.dumps(request_body["business"], separators=(",", ":"))
    param_base64 = base64.b64encode(business_str.encode("utf-8")).decode("utf-8")
    check_sum_src = f"{API_KEY}{cur_time}{param_base64}"
    check_sum = hashlib.md5(check_sum_src.encode("utf-8")).hexdigest()

    headers = {
        "Content-Type": "application/json",
        "X-Appid": APP_ID,
        "X-CurTime": cur_time,
        "X-Param": param_base64,
        "X-CheckSum": check_sum,
    }

    print("=" * 60)
    print("讯飞 TTS API 测试")
    print("=" * 60)
    print(f"APP_ID: {APP_ID}")
    print(f"API_KEY: {API_KEY}")
    print(f"API_SECRET: {API_SECRET}")
    print(f"API_URL: {API_URL}")
    print(f"Text: {text}")
    print(f"Headers: {json.dumps(headers, indent=2)}")
    print(f"Request Body: {json.dumps(request_body, indent=2)}")
    print("=" * 60)

    try:
        response = requests.post(API_URL, headers=headers, json=request_body, timeout=30)
        print(f"\nHTTP Status: {response.status_code}")
        print(f"Response Headers: {dict(response.headers)}")
        print(f"Response Body: {response.text}")

        if response.status_code == 200:
            result = response.json()
            if result.get("code") == 0:
                audio_base64 = result.get("data", {}).get("audio", "")
                print(f"\n✅ 成功！音频数据长度: {len(audio_base64)} chars")
                print("讯飞 TTS API 正常工作")
                return True
            else:
                code = result.get("code")
                message = result.get("message", "")
                print(f"\n❌ API 错误: code={code}, message={message}")

                # 解释常见错误码
                error_codes = {
                    10005: "非法访问",
                    10006: "无效参数",
                    10007: "非法参数",
                    10010: "无授权",
                    10014: "应用未开通该服务",
                    10019: "服务购买失败",
                    10020: "配额不足",
                    10021: "IP 限制",
                }

                explanation = error_codes.get(code, "未知错误")
                print(f"错误解释: {explanation}")

                if code == 10014:
                    print("\n解决方案:")
                    print("1. 登录讯飞控制台 https://www.xfyun.cn/")
                    print("2. 找到应用 APP_ID=5acdb572")
                    print("3. 开通'在线语音合成'服务")
                elif code == 10020:
                    print("\n解决方案:")
                    print("1. 登录讯飞控制台")
                    print("2. 检查配额是否充足")
                    print("3. 购买更多配额或升级套餐")

                return False
        else:
            print(f"\n❌ HTTP 错误: {response.status_code}")
            print(f"Response: {response.text}")

            if response.status_code == 403:
                print("\n403 Forbidden 通常意味着:")
                print("1. 应用未开通 TTS 服务")
                print("2. API 密钥无效或已过期")
                print("3. IP 地址不在白名单")
                print("4. 配额用完")

            return False

    except requests.RequestException as e:
        print(f"\n❌ 网络错误: {e}")
        return False

if __name__ == "__main__":
    success = test_with_correct_params()

    if not success:
        print("\n" + "=" * 60)
        print("下一步建议:")
        print("=" * 60)
        print("1. 登录讯飞控制台 https://www.xfyun.cn/")
        print("2. 检查应用设置")
        print("3. 确认服务开通状态")
        print("4. 检查配额和密钥")
        print("\n临时解决方案:")
        print("- 配置 ElevenLabs API key (推荐)")
        print("- 启动本地 Fish Speech 服务")
        print("=" * 60)
        sys.exit(1)

    sys.exit(0)