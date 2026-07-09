# LXP Assessment System GDD

**系统名称**: LXP Assessment System (语言经验点评估系统)
**版本**: 1.0
**日期**: 2026-06-24
**所属游戏**: LinguaQuest RPG (babble)
**负责服务**: assessment-service
**依赖系统**: voice-service, dialogue-service, content-service, quest-service

---

## 1. Overview

**LXP (Language Experience Points)** 是 LinguaQuest RPG 的核心评估系统，用于量化玩家在游戏中每次语音互动中的语言表现。系统将 ASR 结果与期望答案进行多维度比对，输出 1-5 星评分和对应的 LXP 值。

**系统角色：**
- 作为对话系统的反馈层，在每次语音输入后即时评估
- 作为奖励系统的输入源，LXP 累积影响角色成长和道具获取
- 作为难度调节的传感器，连续低分触发精灵教练干预

---

## 2. Player Fantasy

**玩家体验目标：** "我说英语，游戏听懂我，给我公正的魔法能量"

**叙事包装（与 game-concept.md "魔法能量"框架对齐）：**
星级评分的底层叙事是**魔法能量强度**——玩家每次说出的英语会激活对应强度的魔法能量。1 星 = "微弱但有效的魔法"（不是"差"），5 星 = "强大魔法"。所有星级均为正面结果，不存在"零分"或"失败"。

**情感设计：**
- **成就感**：清晰的魔法能量反馈（星星动画）让玩家感到努力被认可
- **成长感**：对比历史最高分，显示进步轨迹
- **包容性**：容错设计确保害羞或发音不准的孩子也能获得鼓励性评分（2-3 星保底）
- **即时性**：评估结果在 2 秒内呈现，维持心流

**视觉映射：**
| LXP 范围 | 星级（魔法能量） | 反馈语（中文） |
|---------|----------------|--------------|
| 90-100 | ★★★★★ 强大魔法 | "完美！你的发音真棒！" |
| 75-89 | ★★★★☆ 强魔法 | "很棒！继续加油！" |
| 60-74 | ★★★☆☆ 中等魔法 | "不错，还可以更好哦" |
| 40-59 | ★★☆☆☆ 微弱魔法 | "没关系，再试一次" |
| 0-39 | ★☆☆☆☆ 微弱但有效的魔法 | "精灵在仔细听，大声说吧" |

---

## 3. Detailed Rules

### 3.1 触发条件
- 每次 `DialogueManager` 进入 `AWAITING_RESPONSE` 状态后收到语音结果
- 仅对**有期望答案**的对话节点进行评估（自由对话节点只给参与分）

### 3.2 输入数据
```typescript
interface AssessmentInput {
  expectedText: string      // 期望回答文本（英文）
  asrResult: {
    text: string           // ASR 识别文本
    confidence: number     // Whisper 置信度 0-1
    language: string       // 检测语言（en/zh/unknown）
    phonemes?: string[]    // 音素序列（如果可用）
  }
  playerContext: {
    playerId: string
    questId: string
    attemptCount: number   // 当前尝试次数（用于容错加权）
  }
}
```

### 3.3 评估流程

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   接收 ASR 结果  │────▶│   预处理和校验    │────▶│   计算三维度分数  │
│                 │     │  (清理、标准化)   │     │  (accuracy/     │
│                 │     │                  │     │  fluency/vocab) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                            │
┌─────────────────┐     ┌──────────────────┐              │
│   输出星级+LXP   │◀────│   加权汇总+映射   │◀─────────────┘
│   并存档历史     │     │   LXP = Σ(wᵢ×sᵢ) │
└─────────────────┘     └──────────────────┘
```

### 3.4 语言检测规则
- ASR 返回 `language` 字段
- 若为 `zh`：accuracy 维度得 0 分（需要英文回答）
- 若为 `unknown`：尝试通过文本内容检测（简单关键词匹配）
- 静音或无法识别：进入 Edge Case 处理

---

## 4. Formulas

### 4.1 核心公式

$$LXP = accuracy \times 0.4 + fluency \times 0.3 + vocabulary \times 0.3$$

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| accuracy | float | 0-100 | 发音准确度（音素/单词匹配率） |
| fluency | float | 0-100 | 流畅度（语速、停顿、连贯性） |
| vocabulary | float | 0-100 | 词汇多样性（TTR 指数） |
| LXP | float | 0-100 | 最终语言经验点得分 |

**输出范围：** LXP 被钳制在 0-100，然后映射到 1-5 星

---

### 4.2 Accuracy 计算

$$accuracy = \begin{cases}
0 & \text{if } P_{expected} = 0 \text{ or } P_{actual} = 0 \\
\min\left(100, \frac{2 \times P_{match}}{P_{expected} + P_{actual}} \times 100 \times C_{asr}\right) & \text{otherwise}
\end{cases}$$

**边界保护**（防止除以零）：
- 当 ASR 返回空字符串（$P_{expected}=0$ 或 $P_{actual}=0$）时，accuracy = 0
- 触发重试流程，不崩溃

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| P_match | int | 0-∞ | 匹配音素数量（基于编辑距离） |
| P_expected | int | 1-∞ | 期望文本音素数量 |
| P_actual | int | 1-∞ | ASR 结果音素数量 |
| C_asr | float | 0-1 | Whisper 置信度 |

**单词级备选（当音素不可用）：**

$$accuracy_{word} = \begin{cases}
0 & \text{if } W_{expected} = 0 \text{ or } W_{actual} = 0 \\
\frac{2 \times W_{match}}{W_{expected} + W_{actual}} \times 100 \times C_{asr} & \text{otherwise}
\end{cases}$$

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| W_match | int | 0-∞ | 匹配单词数（忽略大小写和标点） |
| W_expected | int | 1-∞ | 期望单词数 |
| W_actual | int | 1-∞ | 实际单词数 |

---

### 4.3 Fluency 计算

$$fluency = \left(0.6 \times R_{normalized} + 0.4 \times C_{pause}\right) \times penalty_{retry}$$

**语速归一化：**

$$R_{normalized} = 100 - \left| \frac{WPM - WPM_{target}}{WPM_{target}} \right| \times 100$$

$$R_{normalized} = \max(0, \min(100, R_{normalized}))$$

**目标语速调整（中国儿童 ESL）**：

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| WPM | float | 0-300 | 实际语速（单词/分钟） |
| WPM_target | float | 60-120 | 目标语速（四年级中国儿童：60 WPM） |
| N_pause | int | 0-∞ | 检测到的停顿次数（>0.5s） |
| attemptCount | int | 1-5 | 当前尝试次数 |

**调整理由**：
- 原目标 WPM_TARGET = 80（母语者四年级标准）
- 中国儿童英语语速普遍低于母语者，正常语速可能被判定为"偏慢"
- 调整为 WPM_TARGET = 60，更符合 ESL 学习者实际表现
- 避免挫败感增加，fluency 维度得分偏低

**停顿惩罚：**

$$C_{pause} = \max(0, 100 - N_{pause} \times 15)$$

**重试惩罚（鼓励一次过）：**

$$penalty_{retry} = \max(0.7, 1 - (attemptCount - 1) \times 0.1)$$

---

### 4.4 Vocabulary 计算

$$vocabulary = TTR \times 100 \times length\_factor$$

$$length\_factor = \min\left(1.0, \frac{N_{total}}{5}\right)$$

**TTR (Type-Token Ratio) 计算：**
- 基于 ASR 结果文本的实际词汇多样性
- 排除期望文本中的词汇（鼓励扩展表达）

**长度归一化因子：**
- 目的：避免短句因 TTR=1.0 得高分，而长句因自然词汇重复被惩罚
- 5词基准：鼓励至少 5 词的回答（符合四年级表达水平）
- 短句示例："Hello" (1词) → length_factor = 0.2 → vocabulary = 1.0×100×0.2 = 20分
- 长句示例："I like blue color" (4词) → length_factor = 0.8 → vocabulary = 1.0×100×0.8 = 80分

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| N_unique | int | 0-∞ | 独特单词数（不重复） |
| N_total | int | 1-∞ | 总单词数 |
| length_factor | float | 0.2-1.0 | 长度归一化因子（5词基准） |

**调整规则：**
- 如果回答包含期望文本中**没有**的合适词汇：+10 分（封顶 100）
- 如果使用了本课新学词汇（来自 content-service）：+5 分/词（封顶 +15）

---

### 4.5 星级映射

$$stars = \begin{cases} 
1 & \text{if } LXP < 40 \\
2 & \text{if } 40 \leq LXP < 60 \\
3 & \text{if } 60 \leq LXP < 75 \\
4 & \text{if } 75 \leq LXP < 90 \\
5 & \text{if } LXP \geq 90
\end{cases}$$

---

### 4.6 完整工作示例

**场景：** SpiritForest 场景，NPC 问 "What color do you like?"
**期望答案：** "I like blue."

**玩家实际回答（ASR 结果）：**
- 识别文本："I like blue color"
- 置信度：0.87
- 语速：75 WPM
- 停顿次数：1
- 尝试次数：1

**计算过程：**

1. **Accuracy**（使用单词级）：
   - W_expected = 3 ("I", "like", "blue")
   - W_actual = 4 ("I", "like", "blue", "color")
   - W_match = 3 ("I", "like", "blue")
   - accuracy = (2×3)/(3+4) × 100 × 0.87 = 6/7 × 87 = **74.6**

2. **Fluency**：
   - WPM_target = 60 (四年级 ESL 中国儿童标准)
   - R_normalized = 100 - |75-60|/60 × 100 = 100 - 25 = **75**
   - C_pause = 100 - 1×15 = **85**
   - penalty_retry = **1.0** (第一次尝试)
   - fluency = (0.6×75 + 0.4×85) × 1.0 = (45 + 34) = **79**

3. **Vocabulary**：
   - N_unique = 4, N_total = 4
   - TTR = 4/4 = 1.0
   - length_factor = min(1.0, 4/5) = 0.8
   - 基础分 = 1.0 × 100 × 0.8 = 80
   - 扩展词汇 "color" 不在期望中：+10（封顶）
   - vocabulary = min(100, 80 + 10) = **90**

4. **LXP**：
   - LXP = 74.6×0.4 + 79×0.3 + 90×0.3
   - LXP = 29.84 + 23.7 + 27 = **80.54**

5. **星级**：
   - 80.54 → **4 星**（"很棒！继续加油！"）

---

## 5. Edge Cases

| 场景 | 检测条件 | 处理方式 | LXP 结果 |
|------|---------|---------|---------|
| ASR 失败 | confidence < 0.3 或 text 为空 | 提示"请再说一遍"，不计入尝试 | 不评分，retry |
| 静音输入 | text 为空 或 时长 < 0.5s | 同上，显示录音提示动画 | 不评分 |
| 中文回答 | language == "zh" 或中文检测触发 | accuracy = 0，其他维度正常计算 | 通常 0-30 分，鼓励说英文 |
| 背景噪音 | confidence 0.3-0.5 且文本乱码 | 同 ASR 失败，额外提示"找个安静的地方" | 不评分 |
| 部分正确 | 识别出关键词但语法错误 | accuracy 按匹配度，vocabulary 奖励正确词 | 2-3 星鼓励 |
| 过度扩展 | 说了期望答案+很多无关内容 | accuracy 降权（分母增大），fluency 可能降 | 中等分数 |
| 重复尝试 | attemptCount > 1 | fluency penalty 生效，保底机制启动 | 最低 40 分保底（2星） |

**Spark 示范模式（与 game-concept.md、core-loop.md 对齐）：**

同一任务 ASR 连续失败 2 次后，评估系统进入"示范模式"：
1. 跳过当前评分，播放 NPC 正确发音（TTS）
2. 玩家跟读，跟读结果也进入评估流程
3. 跟读成功（LXP >= 40）计为任务完成
4. 跟读仍失败 → 保底 40 分（2星），任务仍计为完成
5. 不引入文字输入（保持"纯语音交互"支柱）

此机制确保 ASR 识别率 <85% 时玩家仍有前进路径，消除纯语音交互的单点故障风险。

**保底机制**（与 quest-system.md、star-economy.md 对齐）：

```typescript
// 保底分数（绝对值保底，非系数保底）
// 保底 40 分 = 2 星下限（"微弱魔法"），确保困难玩家不会持续获得 1 星
const MIN_SCORE_RETRY_3 = 40;  // 第3次尝试最低40分（2星）

function calculateFinalLXP(
  raw_lxp: number,
  attempt_count: number
): number {
  // 第3次及以上尝试，保底40分（2星）
  if (attempt_count >= 3 && raw_lxp < MIN_SCORE_RETRY_3) {
    return MIN_SCORE_RETRY_3;
  }
  return raw_lxp;
}
```

**注意**: 这是**绝对值保底**（最低返回40分 = 2星下限），不是**系数保底**（penalty_retry的0.7系数）。保底设为 40 分（而非 30 分），确保困难玩家不会持续获得 1 星（"微弱但有效的魔法"），维持"无失败惩罚"支柱。

---

## 6. Dependencies

### 上游依赖（输入来源）
| 系统 | 数据 | 用途 |
|------|------|------|
| voice-service | ASRResult (text, confidence, phonemes) | 评估核心输入 |
| dialogue-service | expectedText, questContext | 期望答案和场景信息 |
| content-service | vocabularyList, lessonId | 词汇奖励计算 |
| quest-service | attemptCount, playerHistory | 重试次数和历史 |

### 下游依赖（输出去向）
| 系统 | 数据 | 用途 |
|------|------|------|
| reward-service | lxpScore, stars | 奖励计算和发放 |
| spirit-coach-service | score, thresholdBreached | 触发干预提示 |
| quest-service | assessmentResult | 任务进度更新 |
| Godot 客户端 | stars, feedbackText, animations | UI 反馈展示 |

---

## 7. Tuning Knobs

| 参数 | 文件位置 | 默认值 | 安全范围 | 类别 | 说明 |
|------|---------|--------|---------|------|------|
| `ACCURACY_WEIGHT` | `assets/data/lxp_config.json` | 0.4 | 0.3-0.6 | Curve | 发音准确度权重 |
| `FLUENCY_WEIGHT` | `assets/data/lxp_config.json` | 0.3 | 0.2-0.4 | Curve | 流畅度权重 |
| `VOCABULARY_WEIGHT` | `assets/data/lxp_config.json` | 0.3 | 0.2-0.4 | Curve | 词汇多样性权重 |
| `WPM_TARGET` | `assets/data/lxp_config.json` | 60 | 50-80 | Curve | 目标语速（四年级中国儿童 ESL） |
| `WPM_TOLERANCE` | `assets/data/lxp_config.json` | 0.25 | 0.2-0.4 | Curve | 语速偏离容忍度 |
| `PAUSE_PENALTY` | `assets/data/lxp_config.json` | 15 | 10-25 | Curve | 每次停顿扣分 |
| `RETRY_PENALTY_STEP` | `assets/data/lxp_config.json` | 0.1 | 0.05-0.2 | Gate | 重试惩罚递增速率 |
| `RETRY_MIN_PENALTY` | `assets/data/lxp_config.json` | 0.7 | 0.5-0.8 | Gate | 重试惩罚下限 |
| `VOCAB_BONUS_EXPANSION` | `assets/data/lxp_config.json` | 10 | 5-15 | Curve | 扩展词汇奖励 |
| `VOCAB_BONUS_NEW` | `assets/data/lxp_config.json` | 5 | 3-10 | Curve | 新学词汇奖励 |
| `MIN_SCORE_RETRY_3` | `assets/data/lxp_config.json` | 40 | 35-45 | Gate | 第三次尝试保底分（2星下限） |
| `CHILD_PRONUNCIATION_TOLERANCE` | `assets/data/lxp_config.json` | 0.85 | 0.7-0.95 | Curve | 儿童发音宽容度系数（accuracy 最终乘以此系数，对 ESL 儿童放松准确度要求） |
| `STAR_THRESHOLD_5` | `assets/data/lxp_config.json` | 90 | 85-95 | Gate | 五星阈值 |
| `STAR_THRESHOLD_4` | `assets/data/lxp_config.json` | 75 | 70-80 | Gate | 四星阈值 |
| `STAR_THRESHOLD_3` | `assets/data/lxp_config.json` | 60 | 55-65 | Gate | 三星阈值 |
| `STAR_THRESHOLD_2` | `assets/data/lxp_config.json` | 40 | 35-45 | Gate | 二星阈值 |

**年级特定覆盖（ESL 中国儿童）：**
- 三年级：WPM_TARGET = 50
- 四年级：WPM_TARGET = 60（基准）
- 五年级：WPM_TARGET = 70

---

## 8. Acceptance Criteria

### 功能测试
- [ ] 给定示例输入 "I like blue color"，系统输出 86.92 LXP 和 4 星
- [ ] 中文回答 "我喜欢蓝色" → accuracy = 0，LXP < 40，1 星
- [ ] ASR confidence 0.2 → 触发重试流程，不产生评分
- [ ] 第三次尝试 → 应用 0.7 重试惩罚，保底 40 分（2星）
- [ ] 权重总和验证：0.4 + 0.3 + 0.3 = 1.0

### 边界测试
- [ ] 空字符串输入 → 优雅处理，不崩溃
- [ ] 极长回答（50+ 词）→ accuracy 公式正常处理
- [ ] 超快语速（150 WPM）→ R_normalized = 0（封顶）
- [ ] 零单词输入 → 预检查拦截，返回重试

### 性能测试
- [ ] 单次评估计算 < 50ms（不含网络）
- [ ] 并发 100 评估请求，内存稳定

### 集成测试
- [ ] voice-service → assessment-service → reward-service 链路完整
- [ ] 评分结果在 Godot 客户端正确显示为星星动画

---

## 下一步

1. `/design-review design/gdd/lxp-system.md` — 审查此 GDD
2. `/design-system reward-system` — 定义奖励系统（LXP → 奖励映射）
3. `/consistency-check` — 检查与其他 GDD 的变量一致性
4. 实现公式验证测试用例