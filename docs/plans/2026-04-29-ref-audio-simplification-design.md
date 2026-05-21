# Ref Audio 管理简化设计

## 问题

voice-service 和 f5-tts-server 各自维护了一套 ref audio 解析逻辑，存在以下重复和不一致：

- 两套 voice_id → 文件映射表，且 spirit 的映射不一致（spirit.wav vs audio.wav）
- voice-service 读 WAV → base64 编码 → HTTP 传输 → f5-tts-server 解码，同台机器上多余的序列化开销
- f5-tts-server 的 `assets/voices/spirit.wav` 未被代码使用，实际引用的是 `../../shared/assets/voices/`
- `main.py` 中存在声明但从未使用的 `ref_audio_cache = {}` 死代码

## 方案

**f5-tts-server 作为 ref audio 的唯一管理入口**，voice-service 只透传 voice_id 字符串。

### 配置文件：`services/f5-tts-server/voices.json`

```json
{
  "voices": {
    "spirit": {
      "file": "spirit.wav",
      "ref_text": "您通话的客户正在使用呼叫保持服务"
    },
    "scholar": {
      "file": "scholar.wav",
      "ref_text": "Welcome to the academy."
    },
    "merchant": {
      "file": "merchant.wav",
      "ref_text": "Come browse my wares."
    },
    "storyteller": {
      "file": "storyteller.wav",
      "ref_text": "Once upon a time..."
    },
    "receptionist": {
      "file": "receptionist.wav",
      "ref_text": "Welcome to the hotel."
    },
    "street_child": {
      "file": "street_child.wav",
      "ref_text": "Hey mister, got a coin?"
    }
  },
  "audio_dir": "../../shared/assets/voices"
}
```

### f5-tts-server 变更

- `main.py` 启动时加载 `voices.json`
- `/v1/tts` 端点不再接收 `ref_audio` / `ref_text` 字段，仅通过 `voice_id` 查找配置
- 删除硬编码的 `default_refs` dict、base64 解码逻辑、死代码 `ref_audio_cache`

### voice-service 变更

- `fish_client.py`：`synthesize()` 只传 `voice_id` 字符串，不再传 base64 ref_audio
- `tts.py`：移除 `VoiceReferenceManager` 依赖
- **删除** `ref_manager.py`（~90 行）
- ElevenLabs fallback 和 silent WAV fallback 保持不变

### Docker 变更

- voice-service 容器不再需要挂载 `shared/assets/voices`

### 测试变更

- 删除 `test_ref_manager.py`
- 更新 `test_fish_client.py` 和 `test_tts_integration.py` 中的 mock 数据

## 迁移步骤

1. 创建 `voices.json`，合并当前两套映射
2. 修改 f5-tts-server `main.py`
3. 修改 voice-service `fish_client.py`
4. 修改 voice-service `tts.py`
5. 删除 `ref_manager.py` 和对应测试
6. 更新 `docker-compose.dev.yml`
7. 端到端验证

## 净效果

- 删除 ~135 行重复/冗余代码
- ref audio 职责集中于 f5-tts-server
- 消除不必要的 base64 编解码开销
- 配置与代码分离，新增角色只需编辑 JSON
