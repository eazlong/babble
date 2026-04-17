import { describe, it, expect } from 'vitest'
import { performance } from 'perf_hooks'

const API_URL = process.env.API_URL || 'http://localhost:8002'
const COACH_URL = process.env.COACH_URL || 'http://localhost:8005'

interface LatencyStats {
  p95: number
  p99: number
  avg: number
  min: number
  max: number
}

function computeStats(latencies: number[]): LatencyStats {
  const sorted = [...latencies].sort((a, b) => a - b)
  return {
    p95: sorted[Math.floor(sorted.length * 0.95)],
    p99: sorted[Math.floor(sorted.length * 0.99)],
    avg: latencies.reduce((a, b) => a + b, 0) / latencies.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
  }
}

describe('Performance Benchmarks', () => {
  it('voice pipeline P95 latency < 1.5s', async () => {
    const latencies: number[] = []

    for (let i = 0; i < 100; i++) {
      const start = performance.now()
      await simulateVoiceTurn()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    }

    const stats = computeStats(latencies)
    console.log(
      `Voice Pipeline: P95=${stats.p95.toFixed(0)}ms, P99=${stats.p99.toFixed(0)}ms, ` +
        `Avg=${stats.avg.toFixed(0)}ms, Min=${stats.min.toFixed(0)}ms, Max=${stats.max.toFixed(0)}ms`
    )

    expect(stats.p95).toBeLessThan(1500)
    expect(stats.p99).toBeLessThan(2500)
  })

  it('wake word detection < 300ms', async () => {
    const latencies: number[] = []

    for (let i = 0; i < 50; i++) {
      const start = performance.now()
      await simulateWakeWord()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    }

    const stats = computeStats(latencies)
    console.log(
      `Wake Word: Max=${stats.max.toFixed(0)}ms, Avg=${stats.avg.toFixed(0)}ms`
    )

    expect(stats.max).toBeLessThan(300)
  })

  it('spirit coach analysis < 800ms P95', async () => {
    const latencies: number[] = []

    for (let i = 0; i < 50; i++) {
      const start = performance.now()
      await simulateCoachAnalysis()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    }

    const stats = computeStats(latencies)
    console.log(
      `Coach Analysis: P95=${stats.p95.toFixed(0)}ms, P99=${stats.p99.toFixed(0)}ms, Avg=${stats.avg.toFixed(0)}ms`
    )

    expect(stats.p95).toBeLessThan(800)
  })

  it('reward service award < 200ms', async () => {
    const latencies: number[] = []

    for (let i = 0; i < 50; i++) {
      const start = performance.now()
      await simulateRewardAward()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    }

    const stats = computeStats(latencies)
    console.log(
      `Reward Award: P95=${stats.p95.toFixed(0)}ms, P99=${stats.p99.toFixed(0)}ms, Avg=${stats.avg.toFixed(0)}ms`
    )

    expect(stats.p95).toBeLessThan(200)
  })

  it('content filter check < 500ms', async () => {
    const latencies: number[] = []

    for (let i = 0; i < 50; i++) {
      const start = performance.now()
      await simulateContentFilter()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    }

    const stats = computeStats(latencies)
    console.log(
      `Content Filter: P95=${stats.p95.toFixed(0)}ms, P99=${stats.p99.toFixed(0)}ms, Avg=${stats.avg.toFixed(0)}ms`
    )

    expect(stats.p95).toBeLessThan(500)
  })
})

async function simulateVoiceTurn(): Promise<void> {
  const response = await fetch(`${API_URL}/api/v1/dialogue`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      npc_id: 'npc_merchant_01',
      player_input: 'How much does this apple cost?',
      session_id: 'test-session',
      language: 'en',
    }),
  })
  return response.json()
}

async function simulateWakeWord(): Promise<void> {
  await fetch(`${COACH_URL}/api/v1/coach/wake`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ user_id: 'test-user', language: 'zh' }),
  })
}

async function simulateCoachAnalysis(): Promise<void> {
  await fetch(`${COACH_URL}/api/v1/coach/analyze`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      turn_id: 'test-turn',
      asr_text: 'I goed to the store yesterday',
      user_id: 'test-user',
    }),
  })
}

async function simulateRewardAward(): Promise<void> {
  const response = await fetch(`${API_URL.replace('8002', '8007')}/api/v1/rewards/award`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      user_id: 'test-user',
      type: 'lxp',
      amount: 10,
      reason: 'test',
    }),
  })
  return response.json()
}

async function simulateContentFilter(): Promise<void> {
  const response = await fetch(`${API_URL.replace('8002', '8004')}/api/v1/moderation/check`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: 'Hello world', isChildMode: true }),
  })
  return response.json()
}
