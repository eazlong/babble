export interface LLMTokenUsage {
  promptTokens: number
  completionTokens: number
  totalTokens: number
}

export interface LLMCallRecord {
  trigger: 'wake' | 'error' | 'silence'
  latencyMs: number
  fallback: boolean
  tokenUsage?: LLMTokenUsage
}

export interface CoachMetricsSnapshot {
  totalCalls: number
  fallbackCalls: number
  fallbackRate: number
  latencyCount: number
  latencyP50Ms: number
  latencyP95Ms: number
  promptTokens: number
  completionTokens: number
  totalTokens: number
  callsByTrigger: Record<'wake' | 'error' | 'silence', number>
}

const TRIGGERS = ['wake', 'error', 'silence'] as const

export class CoachMetrics {
  private totalCalls = 0
  private fallbackCalls = 0
  private promptTokens = 0
  private completionTokens = 0
  private totalTokens = 0
  private latenciesMs: number[] = []
  private callsByTrigger: Record<'wake' | 'error' | 'silence', number> = {
    wake: 0,
    error: 0,
    silence: 0,
  }

  recordCall(record: LLMCallRecord): void {
    this.totalCalls += 1
    this.callsByTrigger[record.trigger] += 1
    this.latenciesMs.push(Math.max(0, Math.round(record.latencyMs)))

    if (record.fallback) {
      this.fallbackCalls += 1
    }

    if (record.tokenUsage) {
      this.promptTokens += record.tokenUsage.promptTokens
      this.completionTokens += record.tokenUsage.completionTokens
      this.totalTokens += record.tokenUsage.totalTokens
    }
  }

  snapshot(): CoachMetricsSnapshot {
    const sortedLatencies = [...this.latenciesMs].sort((a, b) => a - b)
    return {
      totalCalls: this.totalCalls,
      fallbackCalls: this.fallbackCalls,
      fallbackRate: this.totalCalls === 0 ? 0 : this.fallbackCalls / this.totalCalls,
      latencyCount: sortedLatencies.length,
      latencyP50Ms: percentile(sortedLatencies, 0.5),
      latencyP95Ms: percentile(sortedLatencies, 0.95),
      promptTokens: this.promptTokens,
      completionTokens: this.completionTokens,
      totalTokens: this.totalTokens,
      callsByTrigger: { ...this.callsByTrigger },
    }
  }

  toPrometheus(): string {
    const snap = this.snapshot()
    const lines = [
      '# HELP spirit_coach_llm_calls_total Total LLM coach calls.',
      '# TYPE spirit_coach_llm_calls_total counter',
      `spirit_coach_llm_calls_total ${snap.totalCalls}`,
      '# HELP spirit_coach_llm_fallback_calls_total Total LLM coach fallback calls.',
      '# TYPE spirit_coach_llm_fallback_calls_total counter',
      `spirit_coach_llm_fallback_calls_total ${snap.fallbackCalls}`,
      '# HELP spirit_coach_llm_fallback_rate Current fallback call ratio.',
      '# TYPE spirit_coach_llm_fallback_rate gauge',
      `spirit_coach_llm_fallback_rate ${snap.fallbackRate}`,
      '# HELP spirit_coach_llm_latency_p50_ms P50 LLM coach latency in milliseconds.',
      '# TYPE spirit_coach_llm_latency_p50_ms gauge',
      `spirit_coach_llm_latency_p50_ms ${snap.latencyP50Ms}`,
      '# HELP spirit_coach_llm_latency_p95_ms P95 LLM coach latency in milliseconds.',
      '# TYPE spirit_coach_llm_latency_p95_ms gauge',
      `spirit_coach_llm_latency_p95_ms ${snap.latencyP95Ms}`,
      '# HELP spirit_coach_llm_tokens_total Total tokens reported by the LLM provider.',
      '# TYPE spirit_coach_llm_tokens_total counter',
      `spirit_coach_llm_tokens_total{type="prompt"} ${snap.promptTokens}`,
      `spirit_coach_llm_tokens_total{type="completion"} ${snap.completionTokens}`,
      `spirit_coach_llm_tokens_total{type="total"} ${snap.totalTokens}`,
      '# HELP spirit_coach_llm_calls_by_trigger_total Total LLM coach calls by trigger.',
      '# TYPE spirit_coach_llm_calls_by_trigger_total counter',
      ...TRIGGERS.map((trigger) => `spirit_coach_llm_calls_by_trigger_total{trigger="${trigger}"} ${snap.callsByTrigger[trigger]}`),
    ]
    return `${lines.join('\n')}\n`
  }

  shouldAlertFallbackRate(threshold = 0.05): boolean {
    return this.snapshot().fallbackRate > threshold
  }

  reset(): void {
    this.totalCalls = 0
    this.fallbackCalls = 0
    this.promptTokens = 0
    this.completionTokens = 0
    this.totalTokens = 0
    this.latenciesMs = []
    this.callsByTrigger = { wake: 0, error: 0, silence: 0 }
  }
}

function percentile(sortedValues: number[], percentileValue: number): number {
  if (sortedValues.length === 0) return 0
  const index = Math.ceil(sortedValues.length * percentileValue) - 1
  return sortedValues[Math.min(Math.max(index, 0), sortedValues.length - 1)]
}
