import { describe, expect, it, beforeEach } from 'vitest'
import { CoachMetrics } from '../services/coach-metrics.js'

describe('CoachMetrics', () => {
  let metrics: CoachMetrics

  beforeEach(() => {
    metrics = new CoachMetrics()
  })

  it('starts with zero metrics', () => {
    const snapshot = metrics.snapshot()
    expect(snapshot.totalCalls).toBe(0)
    expect(snapshot.fallbackCalls).toBe(0)
    expect(snapshot.fallbackRate).toBe(0)
    expect(snapshot.latencyP50Ms).toBe(0)
    expect(snapshot.latencyP95Ms).toBe(0)
    expect(snapshot.totalTokens).toBe(0)
  })

  it('records calls, latency, fallback, and token usage', () => {
    metrics.recordCall({
      trigger: 'error',
      latencyMs: 120,
      fallback: false,
      tokenUsage: { promptTokens: 100, completionTokens: 30, totalTokens: 130 },
    })
    metrics.recordCall({
      trigger: 'silence',
      latencyMs: 240,
      fallback: true,
    })

    const snapshot = metrics.snapshot()
    expect(snapshot.totalCalls).toBe(2)
    expect(snapshot.fallbackCalls).toBe(1)
    expect(snapshot.fallbackRate).toBe(0.5)
    expect(snapshot.latencyP50Ms).toBe(120)
    expect(snapshot.latencyP95Ms).toBe(240)
    expect(snapshot.promptTokens).toBe(100)
    expect(snapshot.completionTokens).toBe(30)
    expect(snapshot.totalTokens).toBe(130)
    expect(snapshot.callsByTrigger.error).toBe(1)
    expect(snapshot.callsByTrigger.silence).toBe(1)
  })

  it('alerts when fallback rate exceeds threshold', () => {
    metrics.recordCall({ trigger: 'error', latencyMs: 10, fallback: true })
    metrics.recordCall({ trigger: 'error', latencyMs: 10, fallback: false })
    expect(metrics.shouldAlertFallbackRate(0.05)).toBe(true)
    expect(metrics.shouldAlertFallbackRate(0.9)).toBe(false)
  })

  it('renders Prometheus metrics', () => {
    metrics.recordCall({
      trigger: 'wake',
      latencyMs: 77,
      fallback: false,
      tokenUsage: { promptTokens: 10, completionTokens: 5, totalTokens: 15 },
    })

    const output = metrics.toPrometheus()
    expect(output).toContain('spirit_coach_llm_calls_total 1')
    expect(output).toContain('spirit_coach_llm_fallback_calls_total 0')
    expect(output).toContain('spirit_coach_llm_latency_p50_ms 77')
    expect(output).toContain('spirit_coach_llm_tokens_total{type="total"} 15')
    expect(output).toContain('spirit_coach_llm_calls_by_trigger_total{trigger="wake"} 1')
  })

  it('reset clears all metrics', () => {
    metrics.recordCall({ trigger: 'wake', latencyMs: 77, fallback: true })
    metrics.reset()
    const snapshot = metrics.snapshot()
    expect(snapshot.totalCalls).toBe(0)
    expect(snapshot.fallbackCalls).toBe(0)
    expect(snapshot.latencyP50Ms).toBe(0)
  })
})
