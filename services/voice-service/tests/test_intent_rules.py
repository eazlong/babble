"""规则层单测：把 rule_001–rule_011 逐条变成可执行断言。

契约：`docs/adr/0009-intent-value-contract-and-rule-layer-boundary.md`
本文件只测 `src/services/intent_rules.py`（纯函数、无网络、无 LLM）。
"""

from __future__ import annotations

import pytest

from src.services.intent_rules import (
    CHAR_EDIT_RATIO,
    Hit,
    RuleOptions,
    apply_rules,
    arbitrate,
    edit_distance,
    find_hits,
    normalize,
    strip_shell,
    strip_trailing_question,
    tokens,
)

RESUME_CANDIDATES = [
    "let's go", "lets go", "let us go", "let s go",
    "出发", "走吧", "启程", "继续", "接着", "下一课",
    "next lesson", "set off", "go now", "continue", "resume",
]
MARKET_CANDIDATES = ["Nice to meet you", "Nice to meet you too", "My name is Lily", "I am fine, thank you"]


def _closed_set(text: str, *, question: str = "请跟老师读：Nice to meet you", candidates=None, intent="provide", extracted=None):
    return apply_rules(
        text=text,
        context={
            "npc_question": question,
            "expected_slots": [{"key": "answer", "type": "keyword"}],
            "candidate_answers": candidates if candidates is not None else MARKET_CANDIDATES,
        },
        model_intent=intent,
        model_extracted=extracted if extracted is not None else {},
    )


# ─────────────────────────── 基础工具 ───────────────────────────

def test_normalize_and_tokens_are_language_agnostic() -> None:
    assert normalize("Nice to meet you!") == normalize("nice  to  MEET you")
    assert tokens("Say Nice to meet you") == ["say", "nice", "to", "meet", "you"]
    assert tokens("接着走") == ["接", "着", "走"]
    assert edit_distance("nicetomeetyou", "nicetomeatyou") == 1


# ─────────────────── 召回边界：词数守恒 + 字符距离（rule_004/009） ───────────────────

def test_token_count_gate_separates_learning_errors_from_recognition_errors() -> None:
    """这组是本层存在的理由：cs_042 与 cs_044 的编辑距离**完全相同**，只有词数能区分。"""
    ok = ["Nice to meat you", "Nice to eat you"]           # 识别误差：词数 4 == 候选词数
    bad = ["Nice meet you", "Meet you nice", "Nice to meetchu"]  # 学习错误 / 校准探针：词数 ≠ 4

    for text in ok:
        hits = find_hits(text, MARKET_CANDIDATES)
        assert [h.candidate for h in hits] == ["Nice to meet you"], f"{text!r} 应命中"
    for text in bad:
        token_count = len(tokens(text))
        assert find_hits(text, MARKET_CANDIDATES) == [], f"{text!r} 不应命中（{token_count} 词 ≠ 4）"


def test_edit_distance_alone_would_not_separate_them() -> None:
    """把设计依据写成断言：若只看距离，cs_042 与 cs_044 都是 2，无法区分。"""
    assert edit_distance(normalize("Nice to eat you"), normalize("Nice to meet you")) == 2
    assert edit_distance(normalize("Nice meet you"), normalize("Nice to meet you")) == 2


def test_threshold_must_admit_two_edits_on_a_13_char_candidate() -> None:
    """rule_004 初稿写 15% 会拒掉 cs_042（2/13=15.4%），与"cs_042 必须纠错"自相矛盾 → 取 20%。"""
    assert CHAR_EDIT_RATIO >= 2 / len(normalize("Nice to meet you"))


# ─────────────────────────── 去壳（候选之外） ───────────────────────────

@pytest.mark.parametrize(
    "raw,expected",
    [
        ("我叫王小明", "王小明"),
        ("我是王小明", "王小明"),
        ("我的名字是王小明", "王小明"),
        ("叫我小明吧", "小明吧"),        # strip_shell 只管剥壳；丢尾部语气词在自由槽路径（见 apply_rules 测试）
        ("My name is Lily", "Lily"),
        ("Say Nice to meet you", "Nice to meet you"),
        ("Repeat after me, nice to meet you", "nice to meet you"),
        ("请跟我说：出发", "出发"),
    ],
)
def test_strip_shell_removes_shells_and_instruction_echoes(raw: str, expected: str) -> None:
    stripped, applied = strip_shell(raw)
    assert stripped == expected, f"{raw!r} → {stripped!r}"
    assert applied, f"{raw!r} 应记录命中的壳"


def test_strip_shell_leaves_plain_text_untouched() -> None:
    stripped, applied = strip_shell("王小明")
    assert stripped == "王小明" and applied == []


def test_trailing_question_is_dropped_for_free_slots() -> None:
    """rule_006：附带提问必须丢弃 —— 否则『，你呢？』会进玩家名字并落盘。"""
    assert strip_trailing_question("王小明，你呢？")[0] == "王小明"
    assert strip_trailing_question("王小明")[0] == "王小明"
    assert strip_trailing_question("王小明。")[0] == "王小明"


# ─────────────────────────── 仲裁（rule_002 四级） ───────────────────────────

def _hit(candidate: str, start: int, distance: int = 0) -> Hit:
    return Hit(candidate=candidate, start=start, span_text=candidate, distance=distance, exact=distance == 0)


def test_arbitration_quoted_target_beats_framing_words() -> None:
    """问句里被引号标出的才是本轮目标；顺带提到的词（『我们就继续旅程』）不算。"""
    hits = [_hit("接着", 0), _hit("出发", 3)]
    value, rule = arbitrate(hits, RESUME_CANDIDATES, "请对腓腓说『出发』，我们就继续旅程。")
    assert value == "出发" and "quoted" in rule, (value, rule)

    # 无引号时退到"问句中包含"这一级
    value, rule = arbitrate(hits, RESUME_CANDIDATES, "本轮请说出 出发 这个口令")
    assert value == "出发" and "contains" in rule, (value, rule)


def test_arbitration_tier2_is_substring_scoped_then_tier3_earliest() -> None:
    """第 2 级「最长」**只对子串关系生效**；互不包含的候选按"先说的那个"判。

    cs_039（Nice to meet you too ⊃ Nice to meet you）与 cs_040（My name is Lily 12 字
    vs Nice to meet you 13 字，无包含关系）正好分别钉住这两条路径。
    """
    # 子串关系 → 取更具体的长者（cs_018/cs_039）
    value, rule = arbitrate(
        [_hit("Nice to meet you", 0), _hit("Nice to meet you too", 0)], MARKET_CANDIDATES, None
    )
    assert value == "Nice to meet you too" and "substring" in rule, (value, rule)

    # 无包含关系 → 不得比长度，按首次出现（cs_040）
    value, rule = arbitrate(
        [_hit("My name is Lily", 0), _hit("Nice to meet you", 4)], MARKET_CANDIDATES, None
    )
    assert value == "My name is Lily" and "earliest" in rule, (value, rule)

    # 无包含关系时，即使"更长"也不该靠长度获胜
    longer_first = [_hit("My name is Lily", 4), _hit("Nice to meet you", 0)]
    value, rule = arbitrate(longer_first, MARKET_CANDIDATES, None)
    assert value == "Nice to meet you" and "substring" not in rule, (value, rule)


def test_arbitration_falls_back_to_earliest_occurrence() -> None:
    value, rule = arbitrate(
        [_hit("Nice to meet you", 4), _hit("My name is Lily", 0)], MARKET_CANDIDATES, "请跟老师读这句话。"
    )
    assert value == "My name is Lily" and "earliest" in rule, (value, rule)


# ─────────────────────────── 主入口：封闭题 ───────────────────────────

def test_model_returning_whole_sentence_is_narrowed_to_candidate() -> None:
    """cs_040/cs_058 类：模型把整句塞进 extracted，规则层收窄成候选值。"""
    out = _closed_set("Nice to meet you, my name is Tom")
    assert out.intent == "provide"
    assert out.extracted == {"answer": "Nice to meet you"}
    assert out.verdict_source == "rule" and out.shortcut_hit


def test_canonicalises_span_like_cs_009() -> None:
    """cs_009『接着走』→ 候选『接着』（多出的『走』在候选之外）。"""
    out = apply_rules(
        text="接着走",
        context={
            "npc_question": "请对腓腓说『出发』，我们就继续旅程。",
            "expected_slots": [{"key": "answer", "type": "keyword"}],
            "candidate_answers": RESUME_CANDIDATES,
        },
        model_intent="provide",
        model_extracted={"answer": "接着走"},
    )
    assert out.extracted == {"answer": "接着"}, out


@pytest.mark.parametrize("text", ["Nice meet you", "Meet you nice", "Say Nice meet you"])
def test_learning_errors_are_not_rewritten_but_intent_is_kept(text: str) -> None:
    """rule_003 情形 2：确认不了命中 → 保留 provide、清空 extracted，绝不改判 off_topic。"""
    out = _closed_set(text)
    assert out.intent == "provide", "规则层不得把答对/答错与否改判成 off_topic"
    assert out.extracted == {}
    assert out.verdict_source == "llm"


def test_rule_layer_never_flips_off_topic_into_provide() -> None:
    """rule_003 的第一个"绝不"：句中出现候选也不得把模型的 off_topic 翻成 provide。

    cs_025『我不想出发』就是这条的反例。
    """
    out = _closed_set("我不想出发", candidates=RESUME_CANDIDATES, question="请对腓腓说『出发』", intent="off_topic")
    assert out.intent == "off_topic" and out.extracted == {}


# ─────────────────────────── 主入口：自由槽（rule_001/006/007） ───────────────────────────

def _free_slot(text: str, *, intent="provide", extracted=None):
    return apply_rules(
        text=text,
        context={
            "npc_question": "请告诉腓腓你的中文名。",
            "expected_slots": [{"key": "name", "type": "person_name", "description": "玩家告诉腓腓的中文名"}],
            "expected_answer_type": "player_name",
            "candidate_answers": [],
        },
        model_intent=intent,
        model_extracted=extracted if extracted is not None else {},
    )


@pytest.mark.parametrize(
    "text,expected",
    [
        ("我叫王小明，你呢？", "王小明"),
        ("我是王小明", "王小明"),
        ("我的名字是王小明", "王小明"),
        ("叫我小明吧", "小明"),   # 去壳 + 丢尾部语气词（rule_006 的"附带内容"含语气词）
        ("王小明", "王小明"),
    ],
)
def test_free_slot_keeps_player_value_but_strips_shell(text: str, expected: str) -> None:
    out = _free_slot(text)
    assert out.extracted == {"name": expected}, out


def test_free_slot_value_is_never_rewritten_into_a_value_pool() -> None:
    """rule_001 例外：值池只用于委托提议，绝不写进 extracted。"""
    out = apply_rules(
        text="我叫王小明",
        context={
            "npc_question": "请告诉腓腓你用通用语的名字。",
            "expected_slots": [{
                "key": "name", "type": "person_name",
                "delegatable": True, "value_pool": ["Carl", "Wendy", "Leo"],
            }],
            "candidate_answers": [],
        },
        model_intent="provide",
        model_extracted={},
    )
    assert out.extracted == {"name": "王小明"}
    assert out.extracted["name"] not in {"Carl", "Wendy", "Leo"}


def test_free_slot_negation_from_model_stays_off_topic() -> None:
    """rule_007：含名字的否定句 —— 模型判 off_topic，规则层不得回填（否则用拒绝的名字给孩子命名）。"""
    out = _free_slot("我不想叫小明", intent="off_topic")
    assert out.intent == "off_topic" and out.extracted == {}


# ─────────────────────────── 合法性归一（可选，默认关） ───────────────────────────

def test_delegate_normalisation_is_default_and_can_be_disabled() -> None:
    """rule_005 + ADR-0009 §1 例外：合法性归一**默认开启**，可显式关闭回到纯 rule_003。"""
    context = {
        "npc_question": "请对腓腓说『出发』",
        "expected_slots": [{"key": "answer", "type": "keyword"}],
        "candidate_answers": RESUME_CANDIDATES,
    }
    default = apply_rules(text="随便选一个", context=context, model_intent="delegate")
    assert default.intent == "off_topic"
    assert default.matched_rule == "delegate_requires_delegatable"

    strict = apply_rules(
        text="随便选一个", context=context, model_intent="delegate",
        options=RuleOptions(intent_vetoes=False),
    )
    assert strict.intent == "delegate" and strict.matched_rule is None


def test_rule_layer_only_downgrades_never_upgrades_off_topic() -> None:
    """ADR-0009 §1 例外的硬边：只能把"没有消费者的意图"降到 off_topic，绝不反向。

    这是防止"合法性归一"被慢慢扩成"意图推断"的关键不变量 —— 即使在默认（开启归一）模式下，
    off_topic 也必须原样保留，哪怕句中出现候选、哪怕槽位可委托。
    """
    closed = {
        "npc_question": "请对腓腓说『出发』，我们就继续旅程。",
        "expected_slots": [{"key": "answer", "type": "keyword"}],
        "candidate_answers": RESUME_CANDIDATES,
    }
    delegatable = {
        "npc_question": "请告诉腓腓你用通用语的名字。",
        "expected_slots": [{"key": "name", "type": "person_name", "delegatable": True, "value_pool": ["Carl"]}],
        "candidate_answers": [],
    }
    for text, context in (("我不想出发", closed), ("我不想叫小明", delegatable)):
        out = apply_rules(text=text, context=context, model_intent="off_topic")
        assert out.intent == "off_topic", f"{text!r} 被升级成了 {out.intent}"
        assert out.extracted == {}


def test_delegatable_slot_keeps_delegate() -> None:
    context = {
        "npc_question": "请告诉腓腓你用通用语的名字。",
        "expected_slots": [{"key": "name", "type": "person_name", "delegatable": True, "value_pool": ["Carl"]}],
        "candidate_answers": [],
    }
    out = apply_rules(
        text="你帮我起一个吧", context=context, model_intent="delegate",
        options=RuleOptions(intent_vetoes=True),
    )
    assert out.intent == "delegate" and out.extracted == {}


def test_retraction_after_target_only_when_enabled_and_needs_a_hit() -> None:
    """rule_010：口令 + 撤回标记 → 不作数；但同向加强（cs_067）不受影响。"""
    context = {
        "npc_question": "请对腓腓说『出发』，我们就继续旅程。",
        "expected_slots": [{"key": "answer", "type": "keyword"}],
        "candidate_answers": RESUME_CANDIDATES,
    }
    opts = RuleOptions(intent_vetoes=True)

    retracted = apply_rules(text="出发，等一下", context=context, model_intent="provide", options=opts)
    assert retracted.intent == "off_topic" and retracted.matched_rule == "retraction_after_target"

    reinforced = apply_rules(text="出发，我们走吧", context=context, model_intent="provide", options=opts)
    assert reinforced.intent == "provide", "同向加强不得被当成撤回（cs_067）"


def test_no_slot_declaration_means_no_rule_interference() -> None:
    out = apply_rules(text="随便说点什么", context={}, model_intent="provide")
    assert out.extracted == {} and out.verdict_source == "llm"
