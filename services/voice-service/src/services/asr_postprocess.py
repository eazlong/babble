import asyncio
import json
import os
import time
from typing import Any, Literal

import httpx
from pydantic import BaseModel, Field, ValidationError


FallbackReason = Literal[
    "disabled",
    "missing_context",
    "missing_api_key",
    "timeout",
    "provider_error",
    "invalid_json",
    "schema_error",
]


class ExpectedSlot(BaseModel):
    key: str
    type: str = "string"
    description: str | None = None


class ASRPostprocessContext(BaseModel):
    npc_question: str | None = None
    expected_slots: list[ExpectedSlot] = Field(default_factory=list)
    expected_answer_type: str | None = None
    candidate_answers: list[str] = Field(default_factory=list)
    recent_turns: list[dict[str, str]] = Field(default_factory=list)
    session_id: str | None = None
    user_id: str | None = None
    npc_id: str | None = None
    scene_id: str | None = None
    turn_id: str | None = None
    player_level: str | None = None
    language: str | None = None


class LLMPostprocessOutput(BaseModel):
    corrected_text: str
    correction_applied: bool
    correction_reason: str | None
    extracted: dict[str, str | int | float | bool | None] = Field(default_factory=dict)
    confidence: float = Field(ge=0.0, le=1.0)


class ASRPostprocessResult(BaseModel):
    applied: bool
    corrected_text: str
    correction_reason: str | None
    extracted: dict[str, str | int | float | bool | None]
    confidence: float
    fallback_reason: FallbackReason | None
    model: str | None
    latency_ms: int


class ASRPostprocessor:
    def __init__(self, client: httpx.AsyncClient | None = None):
        self.client = client

    async def process(
        self,
        *,
        text: str,
        asr_confidence: float,
        language: str,
        context: dict[str, Any] | None,
    ) -> dict[str, Any]:
        if os.environ.get("ASR_POSTPROCESS_ENABLED", "true").lower() == "false":
            return self._fallback(text, "disabled")

        if not context:
            return self._fallback(text, "missing_context")

        try:
            parsed_context = ASRPostprocessContext.model_validate(context)
        except ValidationError:
            return self._fallback(text, "missing_context")

        if not parsed_context.npc_question or len(parsed_context.expected_slots) == 0:
            return self._fallback(text, "missing_context")

        api_key = os.environ.get("ASR_POSTPROCESS_API_KEY") or os.environ.get("OPENAI_API_KEY")
        if not api_key:
            return self._fallback(text, "missing_api_key")

        model = os.environ.get("ASR_POSTPROCESS_MODEL", "gpt-5.5")
        timeout_ms = int(os.environ.get("ASR_POSTPROCESS_TIMEOUT_MS", "1500"))
        started = time.monotonic()

        try:
            llm_payload = await asyncio.wait_for(
                self._call_llm(
                    api_key=api_key,
                    model=model,
                    text=text,
                    asr_confidence=asr_confidence,
                    language=language,
                    context=parsed_context,
                ),
                timeout=timeout_ms / 1000,
            )
        except TimeoutError:
            return self._fallback(text, "timeout", latency_ms=timeout_ms)
        except (httpx.HTTPError, RuntimeError):
            return self._fallback(text, "provider_error", latency_ms=self._elapsed_ms(started))

        try:
            parsed = json.loads(llm_payload)
        except json.JSONDecodeError:
            return self._fallback(text, "invalid_json", latency_ms=self._elapsed_ms(started))

        try:
            output = LLMPostprocessOutput.model_validate(parsed)
        except ValidationError:
            return self._fallback(text, "schema_error", latency_ms=self._elapsed_ms(started))

        return ASRPostprocessResult(
            applied=True,
            corrected_text=output.corrected_text,
            correction_reason=output.correction_reason,
            extracted=output.extracted,
            confidence=output.confidence,
            fallback_reason=None,
            model=model,
            latency_ms=self._elapsed_ms(started),
        ).model_dump()

    async def _call_llm(
        self,
        *,
        api_key: str,
        model: str,
        text: str,
        asr_confidence: float,
        language: str,
        context: ASRPostprocessContext,
    ) -> str:
        base_url = os.environ.get("ASR_POSTPROCESS_BASE_URL") or os.environ.get("OPENAI_BASE_URL") or "https://api.openai.com/v1"
        client = self.client or httpx.AsyncClient()
        should_close = self.client is None
        try:
            response = await client.post(
                f"{base_url.rstrip('/')}/chat/completions",
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": model,
                    "messages": [
                        {"role": "system", "content": self._system_prompt()},
                        {"role": "user", "content": self._user_prompt(text, asr_confidence, language, context)},
                    ],
                    "response_format": {"type": "json_object"},
                    "temperature": 0.1,
                    "max_tokens": 300,
                },
            )
            response.raise_for_status()
            data = response.json()
            content = data.get("choices", [{}])[0].get("message", {}).get("content")
            if not isinstance(content, str) or not content:
                raise RuntimeError("Empty LLM response")
            return content
        finally:
            if should_close:
                await client.aclose()

    def _fallback(self, text: str, reason: FallbackReason, latency_ms: int = 0) -> dict[str, Any]:
        return ASRPostprocessResult(
            applied=False,
            corrected_text=text,
            correction_reason=None,
            extracted={},
            confidence=0.0,
            fallback_reason=reason,
            model=None,
            latency_ms=latency_ms,
        ).model_dump()

    def _elapsed_ms(self, started: float) -> int:
        return int((time.monotonic() - started) * 1000)

    def _system_prompt(self) -> str:
        return (
            "You are an ASR post-processor for a children's language-learning RPG. "
            "Correct speech-recognition errors using the provided game context and extract requested slots. "
            "Be conservative. Return valid JSON only. Extract only expected_slots keys."
        )

    def _user_prompt(
        self,
        text: str,
        asr_confidence: float,
        language: str,
        context: ASRPostprocessContext,
    ) -> str:
        return json.dumps(
            {
                "raw_text": text,
                "asr_confidence": asr_confidence,
                "language": language,
                "context": context.model_dump(exclude_none=True),
                "return_shape": {
                    "corrected_text": "string",
                    "correction_applied": "boolean",
                    "correction_reason": "string|null",
                    "extracted": "object",
                    "confidence": "number 0..1",
                },
            },
            ensure_ascii=False,
        )


asr_postprocessor = ASRPostprocessor()
