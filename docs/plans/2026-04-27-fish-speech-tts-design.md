# F5-TTS 本地 TTS 方案设计

## 背景

当前 voice-service 使用 ElevenLabs 云端 API，存在以下问题：
- 需要外网访问，无法离线部署
- 按月订阅费用（$5-99/月）
- 延迟依赖网络质量

目标：用本地模型替代，支持离线部署场景。

## 需求

| 需求项 | 选择 |
|--------|------|
| 部署环境 | 开发：Mac M1/M2/M3 (MLX)；生产：Linux GPU |
| 语音质量 | 平衡自然度与速度，RTF < 1.0 |
| 角色语音 | 动态克隆，运行时上传参考音频 |
| 离线支持 | 必须支持无网络环境 |

## 方案选择

**F5-TTS + MLX（推荐）**

优点：
- 开源 Apache 2.0 许可，比 Fish Speech 的 CC-BY-NC-SA 更宽松
- 原生支持 Apple Silicon (MLX)，无需 Docker
- 4-bit 量化版仅 363MB，内存友好
- Zero-shot voice cloning（3-15秒参考音频）
- 优化后 M1 上 RTF ~0.06（5 秒音频 / 0.28 秒）

缺点：
- 中文质量略逊于 Fish Speech（对儿童游戏足够）
- Mac 上需本地运行，不走 Docker
- 生产部署需 NVIDIA GPU

备选方案（未采纳）：
- Fish Speech v1.5：中文质量更好，但无 ARM64 Docker，CC-BY-NC-SA 许可
- OpenVoice v2：轻量但中文音质略逊
- XTTS v2：项目维护不稳定

## 架构设计

```
voice-service (FastAPI:8301)
    ├── /api/v1/voice/tts → TTSService
    └── 内部调用 → f5-tts-server (localhost:8002)
```

**服务模式：HTTP Server 独立进程**

F5-TTS 以 sidecar 进程运行，FastAPI 通过 httpx 异步调用。

**部署策略：**
- Mac 开发：本地运行 `.venv/bin/python services/f5-tts-server/main.py`
- Linux 生产：使用官方 Docker 镜像 `ghcr.io/swivid/f5-tts:main`

**模型管理：**
- 模型自动下载到 `~/.cache/huggingface/hub/`
- 角色 reference audio 位于 `services/f5-tts-server/assets/voices/`

## 性能参数

| 参数 | 值 | 说明 |
|------|------|------|
| F5_STEPS | 2 | 推理步数（默认8，2步显著提速） |
| F5_METHOD | euler | ODE 求解方法（默认rk4，euler更快） |
| F5_QUANTIZATION_BITS | 0 | 0=不量化，4=4-bit(省内存但稍慢) |

## API 接口设计

**保持现有接口不变：**

```python
# POST /api/v1/voice/tts
{
  "text": "Hello, young traveler!",
  "voice_id": "spirit",
  "language": "en"
}

# Response
{
  "audio_data": "base64...",
  "duration_ms": 1500,
  "format": "wav"
}
```

## 文件结构

```
services/
├── voice-service/              # 主语音服务（ASR + TTS 路由）
│   └── src/services/
│       ├── fish_client.py      # 兼容 F5-TTS / Fish Speech 的 HTTP 客户端
│       ├── ref_manager.py      # Reference audio 管理器
│       └── tts.py              # TTSService（双路由：F5 → ElevenLabs）
└── f5-tts-server/              # F5-TTS MLX 独立服务
    ├── main.py                 # FastAPI HTTP server
    ├── Dockerfile              # Apple Silicon Dockerfile
    ├── requirements.txt
    └── assets/voices/          # 角色参考音频
```

## 环境变量

```bash
# voice-service/.env
FISH_SPEECH_URL=http://localhost:8002

# f5-tts-server 启动参数
F5_STEPS=2              # 推理步数
F5_METHOD=euler         # ODE 方法
F5_QUANTIZATION_BITS=0  # 量化位数 (0=不量化, 4=4-bit)
```

## 实施计划

1. ~~Phase 1**: 创建 f5-tts-server 服务~~ ✓
2. ~~Phase 2**: 更新 fish_client.py 兼容 F5-TTS 格式~~ ✓
3. ~~Phase 3**: Docker 配置更新~~ ✓
4. **Phase 4**: 准备 6 个角色的 reference audio
5. **Phase 5**: 集成测试验证

---

更新日期：2026-04-28
