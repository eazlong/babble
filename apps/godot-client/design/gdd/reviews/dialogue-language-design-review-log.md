# Design Review Log: Dialogue Language System

## Review — 2026-07-07 — Verdict: APPROVED (after revision)
**Scope signal**: M  
**Specialists**: game-designer, systems-designer, gameplay-programmer  
**Blocking items**: 7 | **Recommended**: 11  

### Summary
Initial review verdict was NEEDS REVISION due to missing Player Fantasy section, all-failure template set (0 celebration), ASR 4s delay violating core-loop 1.5s requirement, and undefined state lifecycle. After addressing all 7 blocking items (added Player Fantasy, 3 success templates, parallel ASR with 1.5s timeout, state management definitions, audio concatenation spec, API contracts), verdict changed to APPROVED.

### Key Changes in Revision
1. **§1.3 Player Fantasy** — Added "supported, achievement, safety, magic immersion" framing
2. **§3.4 Success templates** — Added `perfect_success`, `good_attempt`, `breakthrough_success` (priority 14-16)
3. **§2.3 + §3.3 ASR** — Changed from serial fallback (4s) to parallel recognition (1.5s timeout)
4. **§3.4 Template priority** — Fixed conflict: `repeated_failure` priority 9→11, `asr_unclear` added `max: 2`
5. **§3.5 State management** — Defined `fallback_count` (consecutive, reset on success) and `recent_attempts` (10-item rolling window)
6. **§4.3 Audio concatenation** — Specified: voice-service Python + pydub, unified WAV 16bit 24kHz mono
7. **§3.6 API contracts** — Added 3 endpoints: `/asr-parallel`, `/tts-segmented`, `/process` with full request/response schemas

### Prior verdict resolved: First review → APPROVED

## Consistency Fix — 2026-07-07

**Issue**: Threshold inconsistency with core-loop.md and spirit-coach.md

**Before**:
- dialogue-language-design.md: `repeated_failure` at `fallback_count >= 3`
- Missing `fallback_count == 2` case

**After** (aligned with core-loop.md §3.1 + spirit-coach.md §3.6):
- `asr_unclear`: `fallback_count: { max: 1 }` (priority 10) — first failure
- `demonstration_mode`: `fallback_count: { min: 2, max: 2 }` (priority 12) — **NEW**, 2 failures → demonstration mode
- `repeated_failure`: `fallback_count: { min: 3 }` (priority 11) — 3+ failures → DDR

**Result**: Three-tier escalation aligned with existing systems:
1. First failure → encourage + demonstrate (asr_unclear)
2. Second failure → demonstration mode (demonstration_mode)
3. Third+ failure → DDR + simplify (repeated_failure)
