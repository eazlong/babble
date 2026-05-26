# 语音超时检测问题记录

**日期**: 2026-05-25
**涉及模块**: VoicePipeline.gd, DialogueManager.gd, HybridAPI.gd, spirit-coach-service

---

## 当前架构概览

### 第一层：VAD 语音端点检测 (VoicePipeline.gd)
```
麦克风采集 → 音量检测 → 判断说话开始/结束
```
| 参数 | 值 | 说明 |
|------|-----|------|
| `silence_threshold` | 0.005 | 音量阈值，低于此值视为静音 |
| `silence_duration` | 1.5s | 连续静音 1.5s 后判定用户说完 |

### 第二层：对话静默超时 (DialogueManager.gd)
```
NPC 说完话后 15s 内用户未说话 → 触发精灵教练干预
```
| 参数 | 值 | 说明 |
|------|-----|------|
| `silence_timer` | 15s | one_shot Timer，NPC 说完话后启动 |

### 超时处理链路
```
DialogueManager._on_silence_timeout()
  → HybridAPI.publish_coach_silence_timeout(session_id, npc_id, 15000)
  → HTTP POST /api/v1/coach/events
  → Redis xadd coach.input (event_type: silence_timeout)
  → CoachInputConsumer.consumeOnce()
  → TriggerClassifier → trigger: "silence"
  → InterventionPolicy → 检查 30s 冷却
  → CoachHintGenerator → 生成中英双语提示
  → SessionManager.push() → WebSocket 推送 Godot
  → CoachOverlay 显示气泡 (8s TTL) + TTS 播放
```

---

## 问题清单

### P2: 15s 超时硬编码
**位置**: `apps/godot-client/assets/scripts/autoload/DialogueManager.gd:112`
```gdscript
silence_timer.start(15.0)  // 硬编码，不可配置
```
**影响**: 
- 不同场景（简单问候 vs 复杂问题）应有不同的等待时间
- 不同年龄组（6 岁 vs 13 岁）反应速度差异大
- 无法通过配置调整，需要改代码

**建议**: 
- 从服务端配置下发超时时间
- 或根据场景/年龄组动态设置

---

### P2: VAD 静音阈值对儿童不友好
**位置**: `apps/godot-client/assets/scripts/autoload/VoicePipeline.gd:14`
```gdscript
var silence_duration: float = 1.5  // 连续静音 1.5s 判定为说完
```
**影响**:
- 儿童说话中间停顿思考是正常的，1.5s 太短
- 可能导致一句话被截断成多段，每段都不完整
- 影响 ASR 识别准确率（上下文丢失）

**建议**:
- 对儿童模式使用更长的 `silence_duration`（如 2.5-3s）
- 或引入智能 VAD（如 Silero VAD ONNX 模型），能区分"思考停顿"和"说话结束"

---

### P2: 超时后只有教练干预，无降级策略
**位置**: `apps/godot-client/assets/scripts/autoload/DialogueManager.gd:114-117`
```gdscript
func _on_silence_timeout() -> void:
    HybridAPI.publish_coach_silence_timeout(coach_session_id, current_npc_id, 15000)
    // 没有其他处理
```
**影响**:
- 超时后只通知精灵教练，NPC 仍然保持沉默
- 用户可能不知道该怎么办，感觉游戏"卡住"了
- 多次超时后没有递增的降级策略

**建议**:
- 第一次超时：NPC 主动提醒（"你还好吗？" / "Take your time!"）
- 第二次超时：精灵教练介入 + NPC 提示
- 第三次超时：降低任务难度或提供选项

---

### P3: 无累计沉默计数
**位置**: 后端 spirit-coach-service
**影响**:
- 连续多次超时被同等对待，没有递增响应策略
- 无法识别用户是否在持续遇到困难

**建议**:
- Redis 中维护用户超时计数 `silence_count:{user_id}`
- 根据计数调整干预策略（鼓励 → 提示 → 降级难度）
- 对话结束后重置计数

---

### P3: 唤醒词检测粗糙
**位置**: `apps/godot-client/assets/scripts/autoload/DialogueManager.gd:119-121`
```gdscript
func _is_wake_request(text: String) -> bool:
    var lower = text.to_lower()
    return lower.containsn("help") or lower.containsn("帮助")
```
**影响**:
- 字符串包含匹配，误报率高（如 "helpful" 也会触发）
- 不支持多语言（仅中英关键词）
- 没有考虑 ASR 转写错误

**建议**:
- 使用关键词列表 + 模糊匹配
- 或接入本地唤醒词模型（TensorFlow Lite KWS）
