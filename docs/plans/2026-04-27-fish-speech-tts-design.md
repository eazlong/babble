# Fish Speech 本地 TTS 方案设计

## 背景

当前 voice-service 使用 ElevenLabs 云端 API，存在以下问题：
- 需要外网访问，无法离线部署
- 按月订阅费用（$5-99/月）
- 延迟依赖网络质量

目标：用 Fish Speech 本地模型替代，支持离线部署场景。

## 需求

| 需求项 | 选择 |
|--------|------|
| 部署环境 | 测试：CPU only；生产：GPU |
| 语音质量 | 平衡自然度与速度，1-2秒可接受 |
| 角色语音 | 动态克隆，运行时上传参考音频 |
| 离线支持 | 必须支持无网络环境 |

## 方案选择

**Fish Speech v1.5（推荐）**

优点：
- 中文/英文双语质量高，接近 ElevenLabs 水准
- 支持 zero-shot voice cloning（3-10秒参考音频即可）
- 轻量模型 `fish-speech-1.5-small`（约 300MB），适合 CPU 测试
- GPU 上推理约 0.5-1.5 秒
- 项目活跃维护，文档完善

缺点：
- 模型首次下载较大（small: 300MB, full: 1.5GB）
- CPU 上推理较慢（约 3-8 秒）
- 需要独立 HTTP 服务进程

备选方案（未采纳）：
- OpenVoice v2：轻量但中文音质略逊
- XTTS v2：项目维护不稳定

## 架构设计

```
voice-service (FastAPI:8001)
    ├── /api/v1/voice/tts → TTSService
    └── 内部调用 → fish-speech-server (内部:8002)
```

**服务模式：HTTP Server 独立进程**

Fish Speech 以 sidecar 容器运行，FastAPI 通过 httpx 异步调用。优势：
- 不阻塞 FastAPI 主线程
- 可独立重启/扩容
- 支持降级策略

**启动策略：**
- 开发/测试环境：可选启动，无 Fish 时降级到 ElevenLabs 或静音 WAV
- 生产环境：强制启动，启动失败则服务不可用

**模型管理：**
- 预下载模型到 `/models/fish-speech/`（Docker volume）
- 6 个角色各配默认 reference audio（3-5 秒），位于 `assets/voices/`

## API 接口设计

**保持现有接口不变：**

```python
# POST /api/v1/voice/tts
{
  "text": "Hello, young traveler!",
  "voice_id": "spirit",  # 预设 ID / URL / base64://
  "language": "en"
}

# Response
{
  "audio_data": "base64...",  # WAV 格式
  "duration_ms": 1500,
  "format": "wav"
}
```

**动态克隆支持：**

`voice_id` 解析规则：
- `"spirit"` → 使用预设 reference audio
- `"https://..."` → 从 URL 下载参考音频
- `"base64://..."` → 解码 base64 音频数据

## 服务层改造

**重命名与路由：**

`ElevenLabsService` → `TTSService`，内部双路由：

```python
class TTSService:
    def __init__(self):
        self.fish_client = FishSpeechClient()
        self.elevenlabs = ElevenLabsClient()  # fallback
        self.fish_available = False
    
    async def init_fish_speech(self):
        """启动时检查 Fish Speech 可用性"""
        self.fish_available = await self.fish_client.health_check()
        if not self.fish_available:
            logger.warning("Fish Speech unavailable, using ElevenLabs fallback")
    
    async def synthesize_audio(self, text: str, voice_id: str) -> str:
        ref_audio = self.ref_manager.get_reference(voice_id)
        
        if self.fish_available:
            try:
                audio = await self.fish_client.synthesize(text, ref_audio)
                return base64.b64encode(audio).decode()
            except Exception as e:
                logger.error(f"Fish Speech error: {e}")
        
        # Fallback to ElevenLabs
        return await self.elevenlabs.synthesize_audio(text, voice_id)
```

## Fish Speech 客户端

```python
class FishSpeechClient:
    def __init__(self):
        self.base_url = os.environ.get("FISH_SPEECH_URL", "http://localhost:8002")
        self.client = httpx.AsyncClient(timeout=30.0)
        self.healthy = False
    
    async def health_check(self) -> bool:
        try:
            resp = await self.client.get(f"{self.base_url}/health")
            self.healthy = resp.status_code == 200
        except:
            self.healthy = False
        return self.healthy
    
    async def synthesize(self, text: str, ref_audio: bytes | None) -> bytes:
        payload = {
            "text": text,
            "output_format": "wav",
            "latency": "balanced"
        }
        if ref_audio:
            payload["reference_audio"] = base64.b64encode(ref_audio).decode()
        
        resp = await self.client.post(f"{self.base_url}/v1/tts", json=payload)
        return resp.content
```

## Reference Audio 管理

```python
class VoiceReferenceManager:
    VOICE_PATHS = {
        "scholar": "assets/voices/scholar.wav",
        "merchant": "assets/voices/merchant.wav",
        "storyteller": "assets/voices/storyteller.wav",
        "receptionist": "assets/voices/receptionist.wav",
        "street_child": "assets/voices/street_child.wav",
        "spirit": "assets/voices/spirit.wav",
    }
    
    def get_reference(self, voice_id: str) -> bytes | None:
        if voice_id.startswith("http"):
            return self._download(voice_id)
        elif voice_id.startswith("base64://"):
            return base64.b64decode(voice_id[7:])
        elif voice_id in self.VOICE_PATHS:
            return self._load_local(self.VOICE_PATHS[voice_id])
        return None
    
    def _download(self, url: str) -> bytes:
        resp = httpx.get(url, timeout=10.0)
        return resp.content
    
    def _load_local(self, path: str) -> bytes:
        with open(path, "rb") as f:
            return f.read()
```

## Docker 部署配置

**docker-compose.dev.yml 新增：**

```yaml
fish-speech:
  image: fishaudio/fish-speech:latest
  ports: ["8002:8002"]
  environment:
    MODEL_SIZE: small  # 测试用 small，生产改为 full
    DEVICE: cpu        # 测试用 cpu，生产改为 cuda
  volumes:
    - ./models:/models
    - ./assets/voices:/voices

voice-service:
  # ... 现有配置
  environment:
    FISH_SPEECH_URL: http://fish-speech:8002
  depends_on: [redis, fish-speech]
```

**环境变量：**

```bash
# .env 新增
FISH_SPEECH_URL=http://fish-speech:8002
```

## 测试策略

**单元测试：**

- `FishSpeechClient` 初始化与 synthesize 方法
- `VoiceReferenceManager` voice_id 解析（预设/base64/URL）
- Mock httpx response 验证调用逻辑

**集成测试：**

- TTSService Fish Speech 优先策略
- Fish Speech 失败时降级 ElevenLabs
- 动态 reference audio 流程

**E2E 测试：**

- 完整 API 流程：请求 → TTS → 返回音频
- 需要 Fish Speech 服务运行（`@pytest.mark.integration`）

## 文件改动清单

| 文件 | 改动 |
|------|------|
| `src/services/elevenlabs.py` | 重命名为 `tts.py`，添加 Fish Speech 路由 |
| `src/services/fish_client.py` | 新增 Fish Speech HTTP 客户端 |
| `src/services/ref_manager.py` | 新增 reference audio 管理器 |
| `src/api/routes/tts.py` | 保持不变，调用 `tts_service` |
| `src/main.py` | 添加 startup 事件初始化 Fish Speech |
| `docker-compose.dev.yml` | 新增 `fish-speech` sidecar 服务 |
| `requirements.txt` | 无新增依赖（httpx 已有） |
| `.env` | 新增 `FISH_SPEECH_URL` |
| `assets/voices/*.wav` | 新增 6 个预设 reference audio 文件 |

## 实施计划

1. **Phase 1**: 创建 Fish Speech 客户端与 reference manager
2. **Phase 2**: 改造 TTSService，集成双路由
3. **Phase 3**: Docker 配置更新，集成 Fish Speech sidecar
4. **Phase 4**: 编写单元测试与集成测试
5. **Phase 5**: 准备预设 reference audio 文件
6. **Phase 6**: E2E 测试验证

---

设计日期：2026-04-27