"""content_id → 知识项 ID 解析器（CONTEXT.md "content_id 映射"）。

第一版只实现单词类规则推导：content_id 形如 "<scene>_inscribe_<word>"
→ 剥前缀 + 归一化 → "word:<slug>"。
语法/阅读/表达类第一版返回 None（未登记），记入日志，不阻塞聚合。

归一化规则：小写 + trim + 去标点。复数暂不合并（apple/apples 视为不同知识项）。
"""

import re
import logging

logger = logging.getLogger("src.knowledge_item_resolver")

# 单词类 content_id 的可推导前缀约定（<scene>_inscribe_<word>）。
# 复用 WordSpiritLibraryArchiveHallController 的 quest_id 拼接模式。
_INSCRIBE_PREFIX_RE = re.compile(r"^[a-z0-9_]+_inscribe_(.+)$")

# 去标点，保留字母数字和空格。
_PUNCT_RE = re.compile(r"[^a-z0-9 ]+")


def _normalize_slug(text: str) -> str:
    """归一化为知识项 slug：小写、去标点、压缩空白。"""
    text = text.strip().lower()
    text = _PUNCT_RE.sub(" ", text)
    return "_".join(text.split())


def resolve(
    content_id: str,
    target_utterance: str,
    expected_answer_type: str,
) -> str | None:
    """把提示级 content_id 解析为知识项 ID。

    单词类用规则推导；其余类型第一版未登记，返回 None。
    """
    if not content_id:
        return None

    cid = content_id.strip().lower()

    # 单词类：content_id 形如 "<scene>_inscribe_<word>"
    m = _INSCRIBE_PREFIX_RE.match(cid)
    if m:
        slug = _normalize_slug(m.group(1))
        if slug:
            return f"word:{slug}"

    # 回退：若 expected_answer_type 明确是单词类且有 target_utterance，用 target 推导。
    word_types = {"word_pronunciation", "spelling", "letter_name"}
    if expected_answer_type in word_types and target_utterance:
        slug = _normalize_slug(target_utterance)
        if slug:
            return f"word:{slug}"

    # 语法/阅读/表达类第一版未登记。
    logger.debug("unmapped content_id=%s expected_answer_type=%s", content_id, expected_answer_type)
    return None


def item_type_from_id(knowledge_item_id: str) -> str:
    """从知识项 ID 提取类型前缀（word/grammar/reading/expr）。"""
    if ":" in knowledge_item_id:
        return knowledge_item_id.split(":", 1)[0]
    return ""
