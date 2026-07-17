import json
import logging
import os
import time
from typing import Any, Literal

import openai
from pydantic import BaseModel, ConfigDict, Field, ValidationError


logger = logging.getLogger(__name__)


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
    target_intent: str | None = None
    intent_description: str | None = None
    candidate_answers: list[str] = Field(default_factory=list)
    recent_turns: list[dict[str, str]] = Field(default_factory=list)
    session_id: str | None = None
    user_id: str | None = None
    npc_id: str | None = None
    scene_id: str | None = None
    turn_id: str | None = None
    player_level: str | None = None
    language: str | None = None


class ASRGuidanceOutput(BaseModel):
    npc_line: str | None = None


class LLMPostprocessOutput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    corrected_text: str
    correction_applied: bool
    correction_reason: str | None
    extracted: dict[str, str | int | float | bool | None] = Field(default_factory=dict)
    intent_matched: bool = True
    guidance: ASRGuidanceOutput = Field(default_factory=ASRGuidanceOutput)
    confidence: float = Field(ge=0.0, le=1.0)


class ASRPostprocessResult(BaseModel):
    applied: bool
    corrected_text: str
    correction_reason: str | None
    extracted: dict[str, str | int | float | bool | None]
    intent_matched: bool
    guidance: ASRGuidanceOutput
    confidence: float
    fallback_reason: FallbackReason | None
    model: str | None
    latency_ms: int


class ASRPostprocessor:
    def __init__(self, client: openai.AsyncOpenAI | None = None):
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

        base_url = (
            os.environ.get("ASR_POSTPROCESS_BASE_URL")
            or os.environ.get("COACH_LLM_BASE_URL")
            or os.environ.get("OPENAI_BASE_URL")
            or "https://api.openai.com/v1"
        )
        model = (
            os.environ.get("ASR_POSTPROCESS_MODEL")
            or os.environ.get("COACH_LLM_MODEL")
            or "gpt-5.5"
        )
        timeout_ms = int(os.environ.get("ASR_POSTPROCESS_TIMEOUT_MS", "30000"))
        started = time.monotonic()

        try:
            llm_payload = await self._call_llm(
                api_key=api_key,
                base_url=base_url,
                model=model,
                text=text,
                asr_confidence=asr_confidence,
                language=language,
                context=parsed_context,
                timeout_ms=timeout_ms,
            )
        except openai.APITimeoutError:
            logger.warning(
                "[ASR-POSTPROCESS] provider timeout base_url=%s model=%s timeout_ms=%s",
                base_url,
                model,
                timeout_ms,
            )
            return self._fallback(text, "timeout", latency_ms=timeout_ms)
        except openai.APIStatusError as exc:
            message = getattr(exc, "message", str(exc))[:500]
            logger.warning(
                "[ASR-POSTPROCESS] provider api_status_error base_url=%s model=%s status_code=%s message=%r",
                base_url,
                model,
                getattr(exc, "status_code", None),
                message,
            )
            return self._fallback(text, "provider_error", latency_ms=self._elapsed_ms(started))
        except openai.APIError as exc:
            message = getattr(exc, "message", str(exc))[:500]
            logger.warning(
                "[ASR-POSTPROCESS] provider api_error base_url=%s model=%s error_type=%s message=%r",
                base_url,
                model,
                exc.__class__.__name__,
                message,
            )
            return self._fallback(text, "provider_error", latency_ms=self._elapsed_ms(started))
        except RuntimeError as exc:
            logger.warning(
                "[ASR-POSTPROCESS] provider runtime_error model=%s error=%s",
                model,
                str(exc),
            )
            return self._fallback(text, "provider_error", latency_ms=self._elapsed_ms(started))

        try:
            parsed = json.loads(llm_payload)
        except json.JSONDecodeError:
            return self._fallback(text, "invalid_json", latency_ms=self._elapsed_ms(started))

        try:
            output = LLMPostprocessOutput.model_validate(parsed)
        except ValidationError:
            return self._fallback(text, "schema_error", latency_ms=self._elapsed_ms(started))

        extracted = self._filter_extracted(output.extracted, parsed_context)
        return ASRPostprocessResult(
            applied=True,
            corrected_text=output.corrected_text,
            correction_reason=output.correction_reason,
            extracted=extracted,
            intent_matched=output.intent_matched,
            guidance=output.guidance,
            confidence=output.confidence,
            fallback_reason=None,
            model=model,
            latency_ms=self._elapsed_ms(started),
        ).model_dump()

    async def _call_llm(
        self,
        *,
        api_key: str,
        base_url: str,
        model: str,
        text: str,
        asr_confidence: float,
        language: str,
        context: ASRPostprocessContext,
        timeout_ms: int,
    ) -> str:
        client = self.client or openai.AsyncOpenAI(
            api_key=api_key,
            base_url=base_url,
            timeout=timeout_ms / 1000,
        )
        should_close = self.client is None
        try:
            completion = await client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": self._system_prompt()},
                    {"role": "user", "content": self._user_prompt(text, asr_confidence, language, context)},
                ],
                response_format={"type": "json_object"},
                temperature=0.1,
                max_tokens=300,
            )
            content = completion.choices[0].message.content if completion.choices else None
            if not isinstance(content, str) or not content:
                raise RuntimeError("Empty LLM response")
            return content
        finally:
            if should_close:
                await client.close()

    def _filter_extracted(
        self,
        extracted: dict[str, str | int | float | bool | None],
        context: ASRPostprocessContext,
    ) -> dict[str, str | int | float | bool | None]:
        allowed_keys = {slot.key for slot in context.expected_slots}
        return {key: value for key, value in extracted.items() if key in allowed_keys}

    def _fallback(self, text: str, reason: FallbackReason, latency_ms: int = 0) -> dict[str, Any]:
        return ASRPostprocessResult(
            applied=False,
            corrected_text=text,
            correction_reason=None,
            extracted={},
            intent_matched=True,
            guidance=ASRGuidanceOutput(),
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
            "Be conservative. Only correct text when the context strongly supports it. "
            "Extract only the slots listed in expected_slots. Do not invent extra keys. "
            "If candidate_answers is provided for a closed-set question, prefer values from that list. "
            "Decide whether the player's answer satisfies target_intent and intent_description. "
            "If it does not, set intent_matched=false and provide one short, warm NPC guidance line. "
            "The guidance line must be child-friendly, actionable, and safe for the NPC to speak directly. "
            "Do not invent slot values when intent is not matched. Return valid JSON only."
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
                    "extracted": "object containing only expected_slots keys",
                    "intent_matched": "boolean",
                    "guidance": {"npc_line": "string|null"},
                    "confidence": "number 0..1",
                },
            },
            ensure_ascii=False,
        )


asr_postprocessor = ASRPostprocessor()
