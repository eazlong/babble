"""Supabase 客户端单例。

第一版若 SUPABASE_KEY 未配置，返回 None，服务降级为"仅算法无持久化"模式，
便于本地无 Supabase 时仍能跑通算法与报告逻辑。
"""

import logging
from typing import Optional

from src import config

logger = logging.getLogger("src.supabase_client")

_client: Optional[object] = None
_initialized = False


def get_client():
    """返回 supabase 客户端；未配置 key 时返回 None。"""
    global _client, _initialized
    if _initialized:
        return _client
    _initialized = True
    if not config.SUPABASE_KEY:
        logger.warning("SUPABASE_KEY 未配置，summary-service 运行在无持久化模式")
        return None
    try:
        from supabase import create_client
        _client = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)
    except Exception as exc:
        logger.error("supabase 客户端初始化失败: %s", exc)
        _client = None
    return _client
