#!/usr/bin/env tsx
/**
 * Performance report generator.
 * Runs latency benchmarks and outputs a summary report.
 */

import { performance } from 'perf_hooks'

const API_URL = process.env.API_URL || 'http://localhost:8002'
const COACH_URL = process.env.COACH_URL || 'http://localhost:8005'

interface MetricResult {
  name: string
  p95: number
  p99: number
  avg: number
  min: number
  max: number
  samples: number
  passed: boolean
  threshold: number
}

const THRESHOLDS: Record<string, number> = {
  'Voice Pipeline': 1500,
  'Wake Word': 300,
  'Coach Analysis': 800,
  'Reward Award': 200,
  'Content Filter': 500,
}

function computeStats(latencies: number[]) {
  const sorted = [...latencies].sort((a, b) => a - b)
  return {
    p95: sorted[Math.floor(sorted.length * 0.95)],
    p99: sorted[Math.floor(sorted.length * 0.99)],
    avg: latencies.reduce((a, b) => a + b, 0) / latencies.length,
    min: sorted[0],
    max: sorted[sorted.length - 1],
  }
}

async function runBenchmark(
  name: string,
  fn: () => Promise<void>,
  samples: number,
  threshold: number
): Promise<MetricResult> {
  console.log(`Running ${name} (${samples} samples)...`)
  const latencies: number[] = []

  for (let i = 0; i < samples; i++) {
    try {
      const start = performance.now()
      await fn()
      const elapsed = performance.now() - start
      latencies.push(elapsed)
    } catch {
      latencies.push(10000)
    }
  }

  const stats = computeStats(latencies)
  return {
    name,
    ...stats,
    samples,
    passed: stats.p95 < threshold,
    threshold,
  }
}

async function main() {
  console.log('=== LinguaQuest Performance Report ===')
  console.log(`Date: ${new Date().toISOString()}`)
  console.log(`API: ${API_URL}, Coach: ${COACH_URL}\n`)

  const results: MetricResult[] = []

  results.push(
    await runBenchmark('Voice Pipeline', simulateVoiceTurn, 100, THRESHOLDS['Voice Pipeline'])
  )
  results.push(
    await runBenchmark('Wake Word', simulateWakeWord, 50, THRESHOLDS['Wake Word'])
  )
  results.push(
    await runBenchmark('Coach Analysis', simulateCoachAnalysis, 50, THRESHOLDS['Coach Analysis'])
  )
  results.push(
    await runBenchmark('Reward Award', simulateRewardAward, 50, THRESHOLDS['Reward Award'])
  )
  results.push(
    await runBenchmark('Content Filter', simulateContentFilter, 50, THRESHOLDS['Content Filter'])
  )

  console.log('\n=== Results ===\n')
  console.log(
    `${'Metric'.padEnd(20)} | ${'P95'.padStart(8)} | ${'P99'.padStart(8)} | ${'Avg'.padStart(8)} | ${'Min'.padStart(8)} | ${'Max'.padStart(8)} | ${'Status'.padStart(8)}`
  )
  console.log('-'.repeat(95))

  for (const r of results) {
    const status = r.passed ? 'PASS' : 'FAIL'
    console.log(
      `${r.name.padEnd(20)} | ${r.p95.toFixed(0).padStart(6)}ms | ${r.p99.toFixed(0).padStart(6)}ms | ${r.avg.toFixed(0).padStart(6)}ms | ${r.min.toFixed(0).padStart(6)}ms | ${r.max.toFixed(0).padStart(6)}ms | ${status}`
    )
  }

  const passCount = results.filter((r) => r.passed).length
  console.log(`\n${passCount}/${results.length} benchmarks passed`)

  if (passCount < results.length) {
    console.log('\nFailed benchmarks:')
    for (const r of results.filter((r) => !r.passed)) {
      console.log(`  - ${r.name}: P95 ${r.p95.toFixed(0)}ms > threshold ${r.threshold}ms`)
    }
    process.exit(1)
  }
}

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

main().catch(console.error)
