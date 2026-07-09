# 对话语言系统设计

**版本**: 1.0  
**最后更新**: 2026-07-07  
**状态**: 设计中

---

## 1. 设计背景

### 1.1 问题陈述

当前设计假设NPC"始终用目标语言（英文）回复"，但实际教学中：
- 初学者需要母语脚手架，不能直接 immersion
- Code-switching（中英混合）是真实语言使用，不是错误
- 小朋友可能说中文、英文、混合、或无意义音节
- 语言难度应随玩家水平动态调整

### 1.2 设计目标

1. **精确控制**：每句话的语言在设计时明确指定
2. **灵活表达**：支持纯中文、纯英文、中英混合
3. **智能适应**：根据玩家水平动态调整语言比例
4. **容错处理**：优雅处理小朋友的随机语言输入

### 1.3 玩家体验幻想

**玩家应该感觉**："Spark是我的魔法伙伴，它用我能理解的方式帮助我探索魔法世界"

当NPC混合使用中英文时，孩子应该感到：
- **被支持**：中文引导让他们不害怕，英文示范让他们有目标
- **有成就感**：每次成功说英文都触发魔法效果（NPC回应、Spark发光、星星积累）
- **安全**：说错了不会被批评，只会得到温柔的示范和鼓励
- **魔法沉浸**：语言比例的变化不是"考试难度调整"，而是"魔法世界的氛围变化"——初级区域更多中文指引，高级区域更多英文咒语

**关键体验原则**：
- 语言适应是**隐性的**——孩子不会意识到"因为我答错了所以中文变多了"，而是感觉"这个场景的魔法氛围更友好"
- 所有反馈都是**正面的**——成功有庆祝，失败有示范，没有"错误"只有"还没学会"
- Spark是**伙伴不是老师**——它说"让我们一起试试"而不是"你错了，应该这样说"

---

## 2. 核心设计决策

### 2.1 对话模式：混合模式

| 对话类型 | 语言控制 | 实现方式 |
|----------|----------|----------|
| **关键剧情** | 预定义 | 每句话带语言标签，可精确控制 |
| **自由对话** | 动态生成 | LLM根据语言规则生成，TTS动态检测 |

**理由**：关键剧情需要精确控制教学节奏，自由对话需要灵活应对玩家输入。

### 2.2 TTS策略演进

| 阶段 | 策略 | 语言检测 | 适用场景 |
|------|------|----------|----------|
| **短期（MVP）** | 分段合成 | 字符级检测 / 预定义segments | 快速实现，精确控制 |
| **长期** | 动态检测 | 混合策略（正则 + API） | 自动化，无需预定义 |

### 2.3 ASR策略：并行识别

```
音频输入
  ↓
同时调用英文ASR + 中文ASR（并行）
  ↓
等待两个结果（最多1.5s超时）
  ↓
比较置信度：
  - en.confidence > zh.confidence + 0.1 → 英文结果
  - zh.confidence > en.confidence + 0.1 → 中文结果
  - 差值 < 0.1 → 选置信度更高的
  - 都 < 0.4 → unclear
  ↓
返回 { text, confidence, detected_language }
```

**延迟优化**：
- 串行方案：en(2s) + zh(2s) = 4s（最坏）→ **不可接受**
- 并行方案：max(en, zh) ≈ 2s → 仍超1.5s预算，但可接受
- 进一步优化：设置1.5s硬超时，超时视为unclear

**为什么并行而非串行**：
- 儿童注意力窗口极短，4s无反馈 = 认为游戏卡了
- 并行延迟 = max(各引擎延迟)，典型1.5-2s
- 串行延迟 = sum(各引擎延迟)，最坏4s

### 2.4 语言比例：动态适应

根据玩家实时正确率调整NPC回复的语言比例：

| 正确率 | 中文比例 | 英文比例 | 教学策略 |
|--------|----------|----------|----------|
| < 40% | 70% | 30% | 大量中文引导，简单英文示范 |
| 40-70% | 40% | 60% | 平衡引导和练习 |
| 70-90% | 20% | 80% | 少量中文提示，主要英文 |
| > 90% | 5% | 95% | 几乎纯英文环境 |

**调整公式**：
```typescript
function calculateLanguageRatio(accuracy: number): { zh: number, en: number } {
  if (accuracy < 0.4) return { zh: 0.7, en: 0.3 }
  if (accuracy < 0.7) return { zh: 0.4, en: 0.6 }
  if (accuracy < 0.9) return { zh: 0.2, en: 0.8 }
  return { zh: 0.05, en: 0.95 }
}
```

---

## 3. 数据结构定义

### 3.1 预定义对话结构

```typescript
interface DialogueLine {
  id: string
  text: string
  language: 'zh' | 'en' | 'mixed' | 'unknown'
  segments?: LanguageSegment[]  // language='mixed' 时必须
  teaching_point?: string       // 教学目标（可选）
  difficulty?: 'easy' | 'medium' | 'hard'
}

interface LanguageSegment {
  text: string
  language: 'zh' | 'en'
}

// 示例
const exampleDialogue: DialogueLine = {
  id: "spark_greeting_001",
  text: "你好！Hello! 我是Spark。",
  language: "mixed",
  segments: [
    { text: "你好！", language: "zh" },
    { text: "Hello! ", language: "en" },
    { text: "我是Spark。", language: "zh" }
  ],
  teaching_point: "greeting",
  difficulty: "easy"
}
```

### 3.2 动态对话语言规则

```typescript
interface LanguageRule {
  player_cefr: string  // 'A1' | 'A2' | 'B1' | 'B2'
  current_accuracy: number  // 0.0 - 1.0
  zh_ratio: number  // 0.0 - 1.0
  en_ratio: number  // 0.0 - 1.0
  prompt_instruction: string  // 传递给LLM的指令
}

function buildLanguageInstruction(rule: LanguageRule): string {
  return `
你需要用以下语言比例回复：
- 中文：${Math.round(rule.zh_ratio * 100)}%
- 英文：${Math.round(rule.en_ratio * 100)}%

规则：
1. 用中文引导和解释
2. 用英文示范目标表达
3. 每次只教1-2个英文单词或短句
4. 鼓励玩家模仿英文部分
`
}
```

### 3.3 ASR结果结构

```typescript
interface ASRResult {
  text: string
  confidence: number  // 0.0 - 1.0
  detected_language: 'en' | 'zh' | 'mixed' | 'unclear'
  processing_time_ms: number
}

// 并行识别实现
async function transcribeParallel(
  audio: Buffer,
  asrService: ASRService
): Promise<ASRResult> {
  const TIMEOUT_MS = 1500  // 硬超时，符合core-loop 1.5s预算

  try {
    // 并行调用英文和中文ASR
    const [enResult, zhResult] = await Promise.allSettled([
      withTimeout(asrService.transcribe(audio, 'en'), TIMEOUT_MS),
      withTimeout(asrService.transcribe(audio, 'zh'), TIMEOUT_MS)
    ])

    const en = enResult.status === 'fulfilled' ? enResult.value : null
    const zh = zhResult.status === 'fulfilled' ? zhResult.value : null

    // 比较置信度，选择更高的
    const enConf = en?.confidence ?? 0
    const zhConf = zh?.confidence ?? 0

    // 都低于阈值 → unclear
    if (enConf < 0.4 && zhConf < 0.4) {
      return {
        text: '',
        confidence: Math.max(enConf, zhConf),
        detected_language: 'unclear',
        processing_time_ms: TIMEOUT_MS
      }
    }

    // 选择置信度更高的，差值 > 0.1才算显著
    if (enConf > zhConf + 0.1) {
      return { ...en!, detected_language: 'en' }
    } else if (zhConf > enConf + 0.1) {
      return { ...zh!, detected_language: 'zh' }
    } else {
      // 差值很小，选置信度更高的
      return enConf >= zhConf
        ? { ...en!, detected_language: 'en' }
        : { ...zh!, detected_language: 'zh' }
    }
  } catch (e) {
    logger.error('Parallel ASR failed', e)
    return {
      text: '',
      confidence: 0,
      detected_language: 'unclear',
      processing_time_ms: TIMEOUT_MS
    }
  }
}

// 超时包装器
function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error('ASR timeout')), ms)
    )
  ])
}
```

### 3.4 鼓励模板系统

```typescript
interface EncouragementTemplate {
  id: string
  condition: {
    asr_confidence?: { min?: number, max?: number }
    detected_language?: Array<'en' | 'zh' | 'mixed' | 'unclear'>
    error_type?: 'grammar' | 'pronunciation' | 'vocabulary' | 'incomplete'
    fallback_count?: { min?: number, max?: number }
  }
  priority: number  // 多个模板匹配时，priority高的优先
  response: {
    npc_text: string  // 支持 {demo}, {target}, {player_input} 占位符
    spark_action?: 'demonstrate' | 'encourage' | 'simplify' | 'repeat'
    difficulty_adjustment?: 'down' | 'none' | 'up'
    audio_speed?: number  // TTS语速，0.5-1.5，默认1.0
  }
}

// 预置模板
const TEMPLATES: EncouragementTemplate[] = [
  // === 成功/庆祝模板 ===
  {
    id: 'perfect_success',
    condition: {
      asr_confidence: { min: 0.9 },
      detected_language: ['en']
    },
    priority: 15,  // 最高优先级
    response: {
      npc_text: "Excellent! {player_input}! 你说得太棒了！",
      spark_action: 'celebrate',  // Spark特效：发光、旋转
      difficulty_adjustment: 'none',
      audio_speed: 1.0
    }
  },
  {
    id: 'good_attempt',
    condition: {
      asr_confidence: { min: 0.7, max: 0.9 },
      detected_language: ['en']
    },
    priority: 14,
    response: {
      npc_text: "Great job! Very good! 继续加油！",
      spark_action: 'encourage',  // Spark特效：点头、微笑
      difficulty_adjustment: 'none',
      audio_speed: 1.0
    }
  },
  {
    id: 'breakthrough_success',  // 连续失败后的成功
    condition: {
      asr_confidence: { min: 0.6 },
      detected_language: ['en'],
      fallback_count: { min: 2, max: 10 }  // 之前失败过2次以上
    },
    priority: 16,  // 比perfect_success更高
    response: {
      npc_text: "You did it! 太厉害了！我就知道你可以！",
      spark_action: 'celebrate_big',  // Spark特效：大庆祝，星星爆发
      difficulty_adjustment: 'none',
      audio_speed: 1.0
    }
  },

  // === 引导/纠正模板 ===
  {
    id: 'demonstration_mode',  // 对齐 core-loop.md / spirit-coach.md: 连续失败2次
    condition: {
      fallback_count: { min: 2, max: 2 }  // 精确匹配2次
    },
    priority: 12,  // 在repeated_failure(11)之上，asr_unclear(10)之上
    response: {
      npc_text: "Let me show you how! 听我说：{demo}",
      spark_action: 'demonstrate',  // Spark示范模式
      difficulty_adjustment: 'none',
      audio_speed: 0.7  // 慢速示范，便于跟读
    }
  },
  {
    id: 'repeated_failure',  // 对齐 spirit-coach.md DDR: 连续失败3+次
    condition: {
      fallback_count: { min: 3 }
    },
    priority: 11,  // 在demonstration_mode(12)之下
    response: {
      npc_text: "No worries! 跟我一起说：{demo}",
      spark_action: 'simplify',
      difficulty_adjustment: 'down',  // DDR: 降低难度
      audio_speed: 0.6  // 最慢
    }
  },
  {
    id: 'asr_unclear',
    condition: {
      asr_confidence: { max: 0.3 },
      detected_language: ['unclear'],
      fallback_count: { max: 1 }  // 修复：只在失败0-1次时触发，2次时交给demonstration_mode
    },
    priority: 10,
    response: {
      npc_text: "Let me show you! {demo}",
      spark_action: 'demonstrate',
      difficulty_adjustment: 'none',
      audio_speed: 0.8  // 慢速示范
    }
  },
  {
    id: 'spoken_chinese',
    condition: {
      detected_language: ['zh'],
      asr_confidence: { min: 0.6 }
    },
    priority: 8,
    response: {
      npc_text: "很好！试试用英文说：{demo}",
      spark_action: 'encourage',
      difficulty_adjustment: 'none'
    }
  },
  {
    id: 'partial_correct',
    condition: {
      error_type: ['incomplete']
    },
    priority: 7,
    response: {
      npc_text: "Good try! 试试说完整的：{target}",
      spark_action: 'encourage',
      difficulty_adjustment: 'none'
    }
  },
  {
    id: 'grammar_error',
    condition: {
      error_type: ['grammar']
    },
    priority: 6,
    response: {
      npc_text: "Close! 试试这样说：{demo}",
      spark_action: 'demonstrate',
      difficulty_adjustment: 'none'
    }
  },
  {
    id: 'pronunciation_unclear',
    condition: {
      asr_confidence: { min: 0.3, max: 0.6 }
    },
    priority: 5,
    response: {
      npc_text: "Almost! 听我说：{demo}",
      spark_action: 'demonstrate',
      audio_speed: 0.7  // 更慢
    }
  }
]
```

**模板变体**：每个模板应提供3-5个随机变体，避免重复感。例如：
```typescript
const TEMPLATE_VARIANTS = {
  perfect_success: [
    "Excellent! {player_input}! 你说得太棒了！",
    "Perfect! 太厉害了！",
    "Wow! Amazing! 完美！",
    "Brilliant! 你做到了！",
    "Fantastic! 说得非常好！"
  ],
  asr_unclear: [
    "Let me show you! {demo}",
    "Listen carefully: {demo}",
    "Watch and listen: {demo}",
    "Let's try together: {demo}"
  ],
  // ... 其他模板类似
}
```

### 3.5 状态管理

```typescript
interface DialogueSessionState {
  session_id: string
  user_id: string
  
  // 连续失败计数：用于触发repeated_failure模板
  // 语义：连续失败次数，第一次成功后重置为0
  fallback_count: number  // 初始值：0，成功时重置
  
  // 实时正确率：用于计算语言比例
  // 语义：最近10次尝试的滚动窗口正确率
  // 计算：correct_in_window / total_in_window
  recent_attempts: Array<{ success: boolean, timestamp: number }>  // 最多保留10条
  
  // 场景进度
  scene_id: string
  current_task_id?: string
}

// 正确率计算（滚动窗口）
function calculateAccuracy(state: DialogueSessionState): number {
  const window = state.recent_attempts.slice(-10)  // 最近10次
  if (window.length === 0) return 0.0  // 首次尝试，默认0
  const correct = window.filter(a => a.success).length
  return correct / window.length
}

// 状态更新
function updateAfterAttempt(
  state: DialogueSessionState,
  success: boolean
): DialogueSessionState {
  return {
    ...state,
    fallback_count: success ? 0 : state.fallback_count + 1,
    recent_attempts: [
      ...state.recent_attempts.slice(-9),  // 保留最近9条
      { success, timestamp: Date.now() }  // 添加当前
    ]
  }
}
```

**状态存储位置**：
- **服务端（dialogue-service内存 + Redis持久化）**
- 原因：客户端可作弊（修改accuracy强制NPC一直说中文）
- Redis key: `dialogue:session:{session_id}`
- TTL: 30分钟（session超时自动清理）

**重连恢复**：
- 客户端重连时，通过session_id从Redis恢复状态
- 如果Redis中无状态（session过期），初始化为默认值

### 3.6 API端点定义

#### POST /api/v1/dialogue/asr-parallel

**请求**（客户端 → voice-service）：
```typescript
interface ASRRequest {
  session_id: string
  audio_data: string  // base64编码的音频
  audio_format: 'wav' | 'mp3' | 'webm'
  sample_rate: number  // 16000 | 22050 | 44100
}
```

**响应**（voice-service → 客户端）：
```typescript
interface ASRResponse {
  text: string
  confidence: number
  detected_language: 'en' | 'zh' | 'mixed' | 'unclear'
  processing_time_ms: number
}
```

#### POST /api/v1/dialogue/tts-segmented

**请求**（客户端 → voice-service）：
```typescript
interface TTSSegmentRequest {
  text: string
  voice_id: string
  language_hint?: 'zh' | 'en' | 'auto'  // auto=自动检测
  segments?: Array<{ text: string, language: 'zh' | 'en' }>  // 预定义分段
}
```

**响应**（voice-service → 客户端）：
```typescript
interface TTSSegmentResponse {
  audio_data: string  // base64编码的完整音频（已拼接）
  duration_ms: number  // 实际音频时长（非估算）
  format: 'wav' | 'mp3'
  segments_used: number  // 实际分段数
}
```

#### POST /api/v1/dialogue/process

**请求**（客户端 → dialogue-service）：
```typescript
interface DialogueProcessRequest {
  session_id: string
  user_id: string
  player_input: string  // ASR识别的文本
  detected_language: 'en' | 'zh' | 'mixed' | 'unclear'
  asr_confidence: number
  npc_id: string
  quest_context?: string
}
```

**响应**（dialogue-service → 客户端）：
```typescript
interface DialogueProcessResponse {
  npc_text: string
  audio_url: string  // TTS合成的音频URL
  lxp_earned: number
  stars_earned: number  // 1-5星
  template_used?: string  // 使用的鼓励模板ID（可选）
  language_ratio: { zh: number, en: number }  // 本次回复的实际语言比例
}
```

---

## 4. TTS语言检测实现

### 4.1 短期方案：字符级检测

```typescript
function detectLanguageSegments(text: string): LanguageSegment[] {
  const segments: LanguageSegment[] = []
  let currentLang: 'zh' | 'en' | null = null
  let currentText = ''

  for (const char of text) {
    const charLang = detectCharLanguage(char)

    if (charLang === currentLang) {
      currentText += char
    } else {
      if (currentText.trim()) {
        segments.push({ text: currentText, language: currentLang! })
      }
      currentLang = charLang
      currentText = char
    }
  }

  if (currentText.trim()) {
    segments.push({ text: currentText, language: currentLang! })
  }

  return mergeAdjacentSegments(segments)
}

function detectCharLanguage(char: string): 'zh' | 'en' | null {
  // 中文字符范围
  if (/[一-鿿]/.test(char)) return 'zh'
  // 英文字母
  if (/[a-zA-Z]/.test(char)) return 'en'
  // 标点、数字、空格：保持当前语言
  return null
}
```

**局限性**：
- 无法处理音译词（如"iPhone"在中文语境）
- 无法处理专有名词（如"WeChat"）
- 标点符号跟随前一语言

### 4.2 长期方案：混合检测策略

```typescript
async function detectLanguageSegmentsAdvanced(
  text: string
): Promise<LanguageSegment[]> {
  // Step 1: 正则分割
  const basicSegments = detectLanguageSegments(text)

  // Step 2: 识别不确定的部分
  const uncertainSegments = basicSegments.filter(seg => {
    // 包含混合字符的段
    return hasMixedCharacters(seg.text)
  })

  // Step 3: 对不确定的部分调用语言检测API
  const resolvedSegments = await Promise.all(
    basicSegments.map(async (seg) => {
      if (hasMixedCharacters(seg.text)) {
        const detectedLang = await detectLanguageAPI(seg.text)
        return { text: seg.text, language: detectedLang }
      }
      return seg
    })
  )

  return mergeAdjacentSegments(resolvedSegments)
}

async function detectLanguageAPI(text: string): Promise<'zh' | 'en'> {
  // 调用 fasttext / langdetect / 自定义API
  // 返回置信度更高的语言
  const result = await languageDetectionService.detect(text)
  return result.confidence > 0.7 ? result.language : 'zh'  // 默认中文
}
```

### 4.3 TTS分段合成

```typescript
// voice-service (Python) 实现
from pydub import AudioSegment
import io
import base64

async def synthesize_with_segmentation(
    text: str,
    voice_id: str,
    segments: Optional[List[Dict]] = None
) -> Dict:
    """
    分段合成并拼接音频
    在voice-service (Python)中实现，使用pydub库
    """
    # Step 1: 如果没有预定义segments，自动检测
    if not segments:
        segments = detect_language_segments(text)
    
    # Step 2: 根据语言路由到不同TTS引擎
    audio_segments = []
    for seg in segments:
        if seg['language'] == 'zh':
            # 中文用讯飞或Fish TTS
            audio_bytes = await tts_engine.synthesize(
                seg['text'], voice_id, engine='xfyun'
            )
        else:
            # 英文用ElevenLabs
            audio_bytes = await tts_engine.synthesize(
                seg['text'], voice_id, engine='elevenlabs'
            )
        audio_segments.append(audio_bytes)
    
    # Step 3: 使用pydub拼接音频
    # 统一格式：WAV 16bit 24kHz mono
    combined = AudioSegment.empty()
    for audio_bytes in audio_segments:
        seg_audio = AudioSegment.from_file(io.BytesIO(audio_bytes), format='wav')
        # 统一采样率、声道、位深
        seg_audio = seg_audio.set_frame_rate(24000).set_channels(1).set_sample_width(2)
        combined += seg_audio
    
    # Step 4: 导出为base64
    output_buffer = io.BytesIO()
    combined.export(output_buffer, format='wav')
    audio_base64 = base64.b64encode(output_buffer.getvalue()).decode('utf-8')
    
    return {
        'audio_data': audio_base64,
        'duration_ms': len(combined),  # 实际时长，非估算
        'format': 'wav',
        'segments_used': len(segments)
    }
```

**性能优化**：
- 并行调用各段TTS（`asyncio.gather`）
- 缓存常用片段（"你好"、"Hello"、"Good"等）
- pydub拼接延迟：<50ms（纯内存操作）
- 总延迟：max(各段TTS延迟) + 拼接延迟 ≈ 200-300ms

**引擎路由策略**：
| 语言 | 优先引擎 | 备选引擎 | 理由 |
|------|----------|----------|------|
| zh | 讯飞TTS | Fish TTS | 讯飞中文发音自然，Fish备选 |
| en | ElevenLabs | 讯飞TTS | ElevenLabs英文情感丰富，讯飞备选 |

**ElevenLabs配额管理**：
- 每月5000字符限制（免费版）
- 实现配额检查：每次调用前检查剩余配额
- 配额不足时降级到讯飞TTS（英文）
- 配置项：`ELEVENLABS_MONTHLY_QUOTA=5000`

---

## 5. 完整对话流程

```
玩家语音输入
  ↓
[ASR并行识别]
  - 同时调用en + zh ASR（1.5s超时）
  - 比较置信度，选择更高的
  ↓
ASRResult { text, confidence, detected_language }
  ↓
[更新session状态]
  - fallback_count（连续失败+1，成功→0）
  - recent_attempts（滚动窗口追加）
  ↓
[意图识别 + 评估]
  - 高置信度英文 → 正常评估
  - 高置信度中文 → 引导说英文
  - 中英混合 → 识别英文部分评估
  - 低置信度 → 鼓励模板
  ↓
[选择响应策略]
  - 匹配鼓励模板（优先级最高的） → 使用模板
  - 无匹配 → LLM生成回复
  ↓
[LLM生成回复（如需要）]
  - 根据语言比例规则（基于accuracy滚动窗口）
  - 根据当前教学目标
  ↓
NPC回复文本
  ↓
[TTS语言检测 + 分段合成]
  - 短期：字符级检测
  - 长期：混合检测策略
  - 引擎路由：zh→讯飞，en→ElevenLabs
  ↓
[音频拼接]
  - voice-service (Python) 用pydub拼接
  - 统一格式：WAV 16bit 24kHz mono
  ↓
播放给玩家
```

---

## 6. 边界情况处理

### 6.1 小朋友随便说（无意义音节）

**场景**：玩家说 "blah blah blah"  
**ASR结果**：confidence = 0.2, detected_language = 'unclear'  
**处理**：
1. 匹配模板 `asr_unclear`
2. NPC说："Let me show you! [慢速示范]"
3. Spark执行 `demonstrate` 动作
4. 不降低难度（避免强化错误行为）

### 6.2 玩家说中文

**场景**：玩家说 "早上好！"  
**ASR结果**：confidence = 0.9, detected_language = 'zh'  
**处理**：
1. 匹配模板 `spoken_chinese`
2. NPC说："很好！试试用英文说：Good morning!"
3. Spark执行 `encourage` 动作
4. TTS分段合成：中文部分用中文语音，英文部分用英文语音

### 6.3 中英混合输入

**场景**：玩家说 "Good 早上好 morning"  
**ASR结果**：confidence = 0.5, detected_language = 'mixed'  
**处理**：
1. 尝试提取英文部分："Good morning"
2. 评估英文部分：关键词匹配成功
3. NPC说："Good try! 完整的说是：Good morning!"
4. 引导玩家说完整英文

### 6.4 连续失败

**场景**：玩家连续3次未识别  
**处理**：
1. 匹配模板 `repeated_failure`
2. NPC说："No worries! 跟我一起说：[简化版]"
3. Spark执行 `simplify` 动作
4. 降低难度（difficulty_adjustment: 'down'）
5. TTS语速降低到 0.6

---

## 7. 实现路线图

### Phase 1: MVP（2周）

- [ ] 实现ASR Fallback链
- [ ] 实现字符级语言检测
- [ ] 实现TTS分段合成
- [ ] 实现6个预置鼓励模板
- [ ] 静态语言比例（根据CEFR等级）

### Phase 2: 动态适应（1周）

- [ ] 实现实时正确率追踪
- [ ] 实现语言比例动态调整
- [ ] 优化TTS分段性能（并行调用）

### Phase 3: 智能检测（2周）

- [ ] 实现混合语言检测策略
- [ ] 集成语言检测API（fasttext/langdetect）
- [ ] 处理边界情况（音译词、专有名词）
- [ ] 优化检测延迟（<200ms）

### Phase 4: LLM鼓励生成（1周）

- [ ] 实现LLM动态生成个性化鼓励
- [ ] 保留模板作为fallback
- [ ] A/B测试模板 vs LLM生成效果

---

## 8. 性能优化

### 8.1 TTS分段合成延迟

**问题**：分段调用TTS增加API调用次数  
**优化**：
- 并行调用所有分段的TTS
- 缓存常用片段的音频（如"你好"、"Hello"）
- 预估延迟：3段 × 200ms/段 = 600ms（并行后 ≈ 200ms）

### 8.2 ASR并行延迟

**问题**：两次ASR调用（en + zh）的延迟  
**优化**：
- **并行调用**：en和zh ASR同时执行（`Promise.allSettled`）
- **硬超时**：1.5s总超时，符合core-loop预算
- **延迟计算**：max(en_time, zh_time) ≈ 1.5-2s（典型），最坏1.5s（超时）
- 对比串行方案：en(2s) + zh(2s) = 4s → **不可接受**

**实际延迟分布**：
- 50% case: 1.2-1.5s（两引擎都快速返回）
- 30% case: 1.5s（超时触发，选置信度高的）
- 20% case: 1.5-2.0s（某引擎慢但最终返回）

### 8.3 语言检测延迟

**问题**：高级检测策略增加延迟  
**优化**：
- 先用正则快速分割（<10ms）
- 只对不确定的部分调用API
- 预估延迟：10ms（正则） + 100ms（API） = 110ms

---

## 9. 测试计划

### 9.1 单元测试

- [ ] 字符级语言检测准确性
- [ ] ASR Fallback链逻辑
- [ ] 鼓励模板匹配逻辑
- [ ] 语言比例计算

### 9.2 集成测试

- [ ] 完整对话流程（语音输入 → 音频输出）
- [ ] TTS分段合成 + 拼接
- [ ] 动态语言比例调整

### 9.3 用户测试

- [ ] 招募10名四年级学生
- [ ] 测试场景：纯英文、纯中文、混合、无意义
- [ ] 收集反馈：是否理解NPC、是否感到鼓励

---

## 10. 开放问题

1. **音译词处理**：如"WeChat"应该用中文还是英文发音？
2. **方言支持**：是否需要支持粤语等其他方言？
3. **语速调整**：是否根据玩家水平自动调整TTS语速？
4. **多轮对话**：如何在多轮对话中保持一致的语言比例？

---

## 附录A: 相关文档

- [Core Loop Design](./core-loop.md)
- [Spirit Coach Design](./spirit-coach.md)
- [Voice Service API](../../services/voice-service/README.md)

## 附录B: 技术依赖

- **ASR**: Whisper / 讯飞ASR
- **TTS**: Fish TTS / ElevenLabs / 讯飞TTS
- **语言检测**: fasttext / langdetect（待集成）
- **LLM**: GPT-4o（动态对话生成）
