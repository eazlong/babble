"""意图取值规则层（方向 C 的确定性部分）。

契约：`docs/adr/0009-intent-value-contract-and-rule-layer-boundary.md`
裁定：`tests/intent_eval/rulings.jsonl`（rule_001–rule_011）

设计要点
- **纯函数、无状态、不调 LLM**：输入是（玩家话语, 上下文, 模型判决），输出是取值层的结论。
- **权限边界（rule_003）**：本模块是**取值规范化器，不是意图裁判**。默认模式下意图一律沿用模型的
  判定；仅当显式开启 `RuleOptions.intent_vetoes` 时才做两处**窄口径的合法性归一**（见下）。
- 实现顺序（ADR-0009 §4）：模型判意图 → 去壳（候选之外）→ 召回边界（候选之内）→ 仲裁 → 自由槽例外。

为什么需要"词数守恒 + 字符距离阈值"两个条件（实测数据决定，见 rule_004.calibration_data）
    用例                                 归一化编辑距离   词数   结局
    cs_019 "Nice to meat you"   → 候选        1          4    纠正（识别误差）
    cs_042 "Nice to eat you"    → 候选        2          4    纠正（识别误差）
    cs_043 "Nice to meetchu"    → 候选        2          3    不纠正（校准探针，见下）
    cs_044 "Nice meet you"      → 候选        2          3    不纠正（学习错误：漏 to）
    cs_061 "Say Nice meet you"  → 候选        5          4    不纠正（学习错误：漏 to）
可见 cs_042 与 cs_044 的**编辑距离完全相同（都是 2）**，只靠距离阈值无法区分；
区分它们的是**词数**：候选 4 词，cs_042 也是 4 词（eat 一对一替换 meet），cs_044 只有 3 词（漏掉 to）。
所以：候选对齐跨度必须**词数相等**，跨度内才允许字符级差异。

阈值取 0.20（而不是 rule_004 初稿写的 0.15）
    cs_019 距离 1 → 比率 0.077；cs_042 距离 2 → 比率 0.154。若按初稿 0.15，cs_042 **会被拒**，
    与 rule_004「cs_042 必须纠错」的锚点自相矛盾（初稿把 cs_042 误记为"1 处编辑"，实际是 2 —— 已勘误）。
    0.20 同时容纳 cs_042 的词内替换，而 cs_044/043/061 仍被**词数条件**挡住，与阈值无关。

cs_043 的校准结论：**排除**。它是 pronunciation 型渲染（meetchu ≈ meet you），词数 3≠4，
本层按"候选内部不得增删词"拒绝其纠正（rules 允许两种选择，此处显式选"排除"）。
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from typing import Any, Iterable, Sequence

# ─────────────────────────── 可调常量（校准点） ───────────────────────────
# 改动任何一个都必须在 rule_004.calibration_data 里记录，并跑评测确认靶子清单变化。

#: 候选对齐跨度内允许的字符级差异上限（按候选归一化长度计）
CHAR_EDIT_RATIO = 0.20
#: 短候选的最小容忍编辑数（避免 3 字候选被 0 容忍卡死）
CHAR_EDIT_MIN = 1
#: 候选对齐跨度与候选之间的词数差上限。0 = 候选内部不得增删词（rule_004/rule_009 的核心）
TOKEN_DELTA = 0

#: 自由槽的去壳前缀（rule_001 允许的"去壳归一"）。注意客户端 _extract_name 只认前五个，
#: 因此『叫我』这类壳必须由本层剥掉，不能指望客户端。
SHELL_PREFIXES: tuple[str, ...] = (
    "我的名字是", "我的名字叫", "我叫", "我是", "叫我", "大家可以叫我",
    "my name is", "my name's", "i am", "i'm", "im", "this is", "call me",
)

#: 候选**之外**的引导词/指令回声（rule_009：按去壳丢弃，不算"多词"）
INSTRUCTION_PREFIXES: tuple[str, ...] = (
    "please repeat after me", "repeat after me", "please say", "say it", "say",
    "read after me", "read", "跟我说", "跟我读", "请跟我说", "请说", "说", "读",
)

#: rule_010 的撤回性/迟疑性标记（仅在开启 intent_vetoes 时生效）
RETRACTION_MARKERS: tuple[str, ...] = (
    "等一下", "等等", "等一等", "先别", "先不要", "稍等", "先等等", "算了", "别急",
    "wait", "hold on", "hang on", "not yet", "one moment", "just a moment", "never mind",
)

#: 句子切分符（用于丢弃自由槽的附带问句/寒暄）
_SENTENCE_SPLIT = re.compile(r"[。！？!?；;，,、\n]+")
_QUESTION_TAIL = re.compile(r"(你|您)?呢[？?]?$|好吗[？?]?$|对吧[？?]?$|how about you|and you|right\??$")
#: 自由槽尾部的语气词（rule_006 把"语气词"列入必须丢弃的附带内容，如『叫我小明吧』→『小明』）
_TRAILING_PARTICLES = "吧呀啊哦噢嘛啦哟喔呢"


@dataclass(frozen=True)
class RuleOptions:
    """规则层的开关。默认严格遵循 rule_003：不碰意图。"""

    #: 开启后允许两处**窄口径合法性归一**（不是意图推断，详见 normalize_delegate / detect_retraction）
    intent_vetoes: bool = False
    #: 是否启用拼音/近音匹配（需 pypinyin；未装则自动跳过）
    phonetic: bool = True


@dataclass
class RuleOutcome:
    """规则层的结论。字段名对齐 ADR-0009 §3 的契约。"""

    intent: str
    extracted: dict[str, Any]
    verdict_source: str  # "rule" | "llm"
    matched_rule: str | None = None
    matched_candidate: str | None = None
    shortcut_hit: bool = False
    shortcut_confidence: float | None = None
    notes: list[str] = field(default_factory=list)


# ─────────────────────────────── 归一化与距离 ───────────────────────────────

def normalize(text: str) -> str:
    """比较用归一化：NFKC → 小写 → 只留字母数字与 CJK。"""
    text = unicodedata.normalize("NFKC", text or "").lower()
    return "".join(
        ch for ch in text if ch.isalnum() or "\u4e00" <= ch <= "\u9fff"
    )


def tokens(text: str) -> list[str]:
    """切词：拉丁/数字连续段为一个 token，CJK 每字一个 token（不引入分词依赖）。

    输出统一小写，与 `normalize` 口径一致（匹配逻辑在任何情况下都不区分大小写）。
    """
    result: list[str] = []
    buffer = ""
    for ch in (text or "").lower():
        if "\u4e00" <= ch <= "\u9fff":
            if buffer:
                result.append(buffer)
                buffer = ""
            result.append(ch)
        elif ch.isalnum() or ch == "'":
            buffer += ch
        else:
            if buffer:
                result.append(buffer)
                buffer = ""
    if buffer:
        result.append(buffer)
    return [t for t in result if t.strip()]


def edit_distance(a: str, b: str) -> int:
    """Levenshtein 距离（滚动数组）。"""
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(
                min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb))
            )
        previous = current
    return previous[-1]


def _max_edits(candidate: str) -> int:
    return max(CHAR_EDIT_MIN, int(len(normalize(candidate)) * CHAR_EDIT_RATIO))


# ─────────────────────────────── 去壳（候选之外） ───────────────────────────────

def strip_shell(text: str) -> tuple[str, list[str]]:
    """剥掉前导的壳与指令回声（rule_006/rule_009 的"候选之外"）。

    返回 (剥壳后的文本, 命中的壳列表)。大小写不敏感；只剥前导，不碰句内。
    """
    stripped = (text or "").strip()
    applied: list[str] = []
    changed = True
    while changed and stripped:
        changed = False
        lowered = stripped.lower()
        for prefix in tuple(SHELL_PREFIXES) + tuple(INSTRUCTION_PREFIXES):
            if lowered.startswith(prefix.lower()):
                stripped = stripped[len(prefix):].lstrip(" ,，、:：")
                applied.append(prefix)
                changed = True
                break
    return stripped, applied


def strip_trailing_question(text: str) -> tuple[str, bool]:
    """丢掉附带的问句/寒暄（rule_006："必须同时丢弃附带内容"）。

    策略保守：只在**第一个句读之后**出现问句/呼语片段时截断，且绝不把整句清空。
    """
    trimmed = (text or "").strip().strip("，,。.!！?？、;；:：")
    parts = [p for p in _SENTENCE_SPLIT.split(trimmed) if p.strip()]
    if len(parts) <= 1:
        return ("" if _QUESTION_TAIL.search(trimmed) else trimmed), False
    kept: list[str] = []
    dropped = False
    for part in parts:
        if _QUESTION_TAIL.search(part.strip()):
            dropped = True
            break
        kept.append(part.strip())
    if not kept:
        return parts[0].strip(), False
    return "".join(kept) if _is_cjk(kept[0]) else " ".join(kept), dropped


def _is_cjk(text: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in text or "")


# ─────────────────────────────── 召回边界（候选之内） ───────────────────────────────

@dataclass(frozen=True)
class Hit:
    candidate: str
    start: int
    span_text: str
    distance: int
    exact: bool


def find_hits(text: str, candidates: Sequence[str]) -> list[Hit]:
    """在话语中找候选命中：**词数守恒的对齐跨度 + 跨度内字符级差异 ≤ 阈值**。

    这是 rule_004/rule_009 的可执行形式：
    - 跨度词数必须等于候选词数（`TOKEN_DELTA`）→ 挡住漏词/多词/乱序等学习错误；
    - 跨度内允许字符级差异（近音、拼读、错字）→ 容纳识别误差；
    - 候选之外的内容不参与对齐 → 天然实现"去壳"（前后多余内容不影响命中）。
    """
    words = tokens(text)
    hits: list[Hit] = []
    for candidate in candidates:
        cand_words = tokens(candidate)
        if not cand_words:
            continue
        cand_norm = normalize(candidate)
        budget = _max_edits(candidate) + TOKEN_DELTA
        for start in range(0, max(0, len(words) - len(cand_words)) + 1):
            span_words = words[start:start + len(cand_words)]
            if len(span_words) != len(cand_words):
                continue
            span_text = "".join(span_words) if _is_cjk(candidate) else " ".join(span_words)
            distance = edit_distance(normalize(span_text), cand_norm)
            if distance <= budget:
                hits.append(
                    Hit(
                        candidate=candidate,
                        start=start,
                        span_text=span_text,
                        distance=distance,
                        exact=distance == 0,
                    )
                )
    # **精确命中优先于模糊命中**：模糊纠错的职责是"救回近音误听"，不是压过精确匹配。
    # 反例（未加这条时实测到的）：『Nice to meet you, my name is Tom』里，
    # 5 词窗口 [nice,to,meet,you,my] 与候选 `Nice to meet you too` 只差 2 个字符（my→too），
    # 落在 20% 预算内 → 规则层凭空补出玩家没说过的 "too"。字符距离无法区分
    # "eat→meet（近音误听）"与"my→too（凭空补词）"，但"是否存在精确命中"可以。
    exact_hits = [h for h in hits if h.exact]
    return exact_hits or hits


def _quoted_segments(question: str) -> list[str]:
    """取出问句里被引号标出的片段 —— 这是"本轮到底要玩家说什么"的最强信号。

    比赛两个场景：『请对腓腓说『出发』，我们就继续旅程。』（引号标出目标）与
    『请跟老师读：Nice to meet you』（无引号，只能退到包含关系）。
    """
    segments: list[str] = []
    for opener, closer in (("『", "』"), ("「", "」"), ("“", "”"), ('"', '"'), ("'", "'")):
        start = 0
        while True:
            left = question.find(opener, start)
            if left < 0:
                break
            right = question.find(closer, left + 1)
            if right < 0:
                break
            segments.append(question[left + 1:right])
            start = right + 1
    return [s for s in segments if s.strip()]


def arbitrate(
    hits: Sequence[Hit], candidates: Sequence[str], npc_question: str | None
) -> tuple[str, str]:
    """rule_002 的仲裁（含两处依实测的细化，见 rulings.jsonl 的 rule_002.refinements）：

    1. **子串关系取最长** —— 玩家说了更完整的表述就记更完整的（cs_018 `Nice to meet you too`
       ⊃ `Nice to meet you`、cs_039 同型）。这一级必须排在"本轮目标"之前：否则问句里恰好含
       较短候选时会把玩家真正说的长句丢掉（cs_018 就是被这条弄坏的）。
    2. **问句中被引号标出的目标** —— 『请对腓腓说『出发』』里的 `出发`（cs_037/cs_038）。
       比"包含关系"强：问句可能顺带提到别的候选（『我们就继续旅程』提到 `继续`）。
    3. **问句中包含的候选** —— 无引号时退到包含关系（cs_041）。
    4. **首次出现位置** —— 互不包含且问句无线索时，按玩家先说的那个（cs_040）。
    5. **候选表顺序** —— 仅对完全相同的候选才可能触发。
    """
    if not hits:
        raise ValueError("arbitrate 需要至少一个命中")
    if len(hits) == 1:
        return hits[0].candidate, "single_hit"

    normalized = {id(h): normalize(h.candidate) for h in hits}
    rule: str | None = None

    # 1. 子串关系 → 取最长的命中
    substring_related = any(
        normalized[id(a)] != normalized[id(b)] and normalized[id(a)] in normalized[id(b)]
        for a in hits for b in hits
    )
    if substring_related:
        longest = max(len(normalized[id(h)]) for h in hits)
        hits = [h for h in hits if len(normalized[id(h)]) == longest]
        rule = "tier1_substring_longest"
        if len(hits) == 1:
            return hits[0].candidate, rule

    # 2/3. 本轮目标：引号标出的 > 问句中包含的
    question = normalize(npc_question or "")
    if question:
        quoted = normalize(" ".join(_quoted_segments(npc_question or "")))
        for label, haystack in (("tier2_quoted_target", quoted), ("tier3_question_contains", question)):
            if not haystack:
                continue
            preferred = [h for h in hits if normalized[id(h)] and normalized[id(h)] in haystack]
            if preferred and len(preferred) < len(hits):
                hits = preferred
                rule = (rule + "+" if rule else "") + label
                break
            if preferred and len(preferred) == len(hits) and label == "tier2_quoted_target":
                # 引号目标命中全部剩余命中：仍是有效信号，但区分不了，继续往下
                continue
        if len(hits) == 1:
            return hits[0].candidate, rule or "tier3_question_contains"

    # 4. 首次出现位置
    earliest = min(h.start for h in hits)
    hits = [h for h in hits if h.start == earliest]
    if len(hits) == 1:
        return hits[0].candidate, (rule + "+" if rule else "") + "tier4_earliest"

    # 5. 候选表顺序
    order = {normalize(c): index for index, c in enumerate(candidates)}
    hits = sorted(hits, key=lambda h: order.get(normalize(h.candidate), 999))
    return hits[0].candidate, (rule + "+" if rule else "") + "tier5_table_order"


# ─────────────────────────────── 合法性归一（可选，默认关） ───────────────────────────────

def normalize_delegate(intent: str, context: dict[str, Any]) -> tuple[str, str | None]:
    """rule_005：`delegate` 只在槽位声明 `delegatable` 时才成立。

    这是**标签合法性归一**，不是意图推断：没有可委托槽位时 `delegate` 没有完成器，
    客户端只能当"没作答"处理（等价于 off_topic）。仅在 `RuleOptions.intent_vetoes=True` 时生效。
    """
    if intent != "delegate":
        return intent, None
    slots = context.get("expected_slots") or []
    if any(slot.get("delegatable") for slot in slots):
        return intent, None
    return "off_topic", "delegate_requires_delegatable"


def detect_retraction(intent: str, text: str, hits: Sequence[Hit]) -> tuple[str, str | None]:
    """rule_010：口令之后紧跟撤回性内容 → 不作数。

    只在**已命中候选**且撤回标记出现在命中之后时成立（避免把"口令后有内容"一概当成撤回，
    cs_067『出发，我们走吧』就是反例）。仅在 `RuleOptions.intent_vetoes=True` 时生效。
    """
    if intent != "provide" or not hits:
        return intent, None
    lowered = (text or "").lower()
    tail_start = max(hit.start for hit in hits)
    tail = "".join(tokens(text)[tail_start:]).lower()
    for marker in RETRACTION_MARKERS:
        if marker.lower() in tail or marker.lower() in lowered.split("...")[-1]:
            return "off_topic", "retraction_after_target"
    return intent, None


# ─────────────────────────────── 主入口 ───────────────────────────────

def apply_rules(
    *,
    text: str,
    context: dict[str, Any],
    model_intent: str,
    model_extracted: dict[str, Any] | None = None,
    options: RuleOptions | None = None,
) -> RuleOutcome:
    """把规则层应用到一次模型判决上。

    `text` 在生产路径上应为 `corrected_text`（纠错后的话语）；回放验证时可用原始 `raw_text`。
    """
    options = options or RuleOptions()
    context = context or {}
    intent = model_intent

    if options.intent_vetoes:
        intent, veto_rule = normalize_delegate(intent, context)
    else:
        veto_rule = None
    notes: list[str] = []

    # 意图不是 provide → 规则层不介入取值（rule_003 情形 3）
    if intent != "provide":
        return RuleOutcome(
            intent=intent,
            extracted={},
            verdict_source="llm",
            matched_rule=veto_rule,
            notes=notes + (["delegate 合法性归一"] if veto_rule else []),
        )

    slots = context.get("expected_slots") or []
    if not slots:
        return RuleOutcome(intent=intent, extracted={}, verdict_source="llm", notes=notes + ["无槽位声明"])

    slot = slots[0]
    key = str(slot.get("key") or "answer")
    candidates = [str(c) for c in (context.get("candidate_answers") or []) if str(c).strip()]
    stripped, shells = strip_shell(text)

    if candidates:
        hits = find_hits(text, candidates)
        if options.intent_vetoes:
            intent, retract_rule = detect_retraction(intent, text, hits)
            if retract_rule:
                return RuleOutcome(
                    intent=intent,
                    extracted={},
                    verdict_source="llm",
                    matched_rule=retract_rule,
                    notes=notes + ["撤回性附带内容 → 不作数"],
                )
        if not hits:
            # rule_003 情形 2：确认不了命中 → 保留 provide、清空取值，绝不改判 off_topic
            return RuleOutcome(
                intent=intent,
                extracted={},
                verdict_source="llm",
                notes=notes + ["候选未确认命中 → 清空 extracted"],
            )
        value, rule_name = arbitrate(hits, candidates, context.get("npc_question"))
        best = min(hits, key=lambda h: h.distance)
        return RuleOutcome(
            intent=intent,
            extracted={key: value},
            verdict_source="rule",
            matched_rule=rule_name,
            matched_candidate=value,
            shortcut_hit=True,
            shortcut_confidence=round(1.0 - best.distance / max(1, len(normalize(value))), 4),
            notes=notes + (["去壳:" + ",".join(shells)] if shells else []),
        )

    # 自由槽（rule_001 例外 / rule_006）：保留玩家说出的值，只去壳 + 丢附带内容
    cleaned, dropped = strip_trailing_question(stripped)
    value = cleaned.strip().strip("，,。.!！?？、;；:：")
    trimmed_particles = value.rstrip(_TRAILING_PARTICLES)
    if trimmed_particles:
        dropped = dropped or trimmed_particles != value
        value = trimmed_particles
    if not value:
        return RuleOutcome(
            intent=intent,
            extracted={},
            verdict_source="llm",
            notes=notes + ["自由槽去壳后为空 → 清空 extracted"],
        )
    return RuleOutcome(
        intent=intent,
        extracted={key: value},
        verdict_source="rule" if (shells or dropped) else "llm",
        matched_rule="free_slot_shell_strip" if (shells or dropped) else None,
        matched_candidate=None,
        shortcut_hit=bool(shells or dropped),
        notes=notes + (["去壳:" + ",".join(shells)] if shells else []) + (["丢弃附带问句"] if dropped else []),
    )
