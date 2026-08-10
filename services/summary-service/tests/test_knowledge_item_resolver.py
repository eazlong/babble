"""knowledge_item_resolver 单元测试：content_id 推导。"""

from src.services import knowledge_item_resolver as kir


class TestResolveWordFromInscribeContentId:
    def test_archive_inscribe_apple(self):
        assert kir.resolve("archive_inscribe_apple", "APPLE", "word_pronunciation") == "word:apple"

    def test_case_insensitive_content_id(self):
        assert kir.resolve("Archive_Inscribe_Apple", "APPLE", "word_pronunciation") == "word:apple"

    def test_word_with_spaces_normalized(self):
        # 多词 target 归一化为下划线
        assert kir.resolve("archive_inscribe_ice_cream", "ICE CREAM", "word_pronunciation") == "word:ice_cream"

    def test_punctuation_stripped(self):
        assert kir.resolve("archive_inscribe_apple", "apple!", "word_pronunciation") == "word:apple"


class TestResolveFallbackByAnswerType:
    def test_word_pronunciation_uses_target(self):
        # content_id 不匹配 inscribe 约定，但 answer_type 是单词类且有 target
        assert kir.resolve("some_other_prompt", "banana", "word_pronunciation") == "word:banana"

    def test_spelling_uses_target(self):
        assert kir.resolve("custom_id", "cat", "spelling") == "word:cat"


class TestResolveUnmapped:
    def test_grammar_returns_none(self):
        assert kir.resolve("archive_grammar_q1", "", "grammar_judge") is None

    def test_reading_returns_none(self):
        assert kir.resolve("reading_passage_1", "", "reading_infer") is None

    def test_empty_content_id_no_target_returns_none(self):
        assert kir.resolve("", "", "short_answer") is None

    def test_non_word_no_target_returns_none(self):
        assert kir.resolve("dialogue_greet", "", "short_answer") is None


class TestItemTypeFromId:
    def test_word(self):
        assert kir.item_type_from_id("word:apple") == "word"

    def test_grammar(self):
        assert kir.item_type_from_id("grammar:present_simple") == "grammar"

    def test_no_prefix(self):
        assert kir.item_type_from_id("bare") == ""
