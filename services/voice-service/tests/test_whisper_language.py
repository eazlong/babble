from src.services.whisper import _normalize_whisper_language


def test_normalize_whisper_language_cn_en_to_zh():
    assert _normalize_whisper_language("cn_en") == "zh"


def test_normalize_whisper_language_zh_cn_to_zh():
    assert _normalize_whisper_language("zh-CN") == "zh"


def test_normalize_whisper_language_auto_to_none():
    assert _normalize_whisper_language("auto") is None


def test_normalize_whisper_language_empty_to_none():
    assert _normalize_whisper_language("") is None


def test_normalize_whisper_language_en_stays_en():
    assert _normalize_whisper_language("en") == "en"
