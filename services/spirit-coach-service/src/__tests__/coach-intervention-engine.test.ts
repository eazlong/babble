import { describe, expect, it, vi } from 'vitest'
import { CoachInterventionEngine } from '../services/coach-intervention-engine.js'
import type { CoachInput, CoachResponse } from '../types/coach-events.js'

function makeDialogueInput(overrides: Partial<CoachInput> = {}): CoachInput {
  return {
    event_type: 'dialogue_turn',
    session_id: 'session-1',
    user_id: 'user-1',
    npc_id: 'npc-1',
    player_text: 'I am go',
    npc_response: 'Great!',
    language: 'en',
    timestamp: 1779177600000,
    player_level: 'A1',
    recent_turns: [],
    ...overrides,
  } as CoachInput
}

function createResponse(overrides: Partial<CoachResponse> = {}): CoachResponse {
  return {
    text: '喵~ 差一点点！可以说：I am going',
    repeat_phrase: 'I am going',
    emotion: 'encourage',
    should_tts: true,
    ttl_ms: 8000,
    ...overrides,
  }
}

function createStreakTracker() {
  return {
    recordError: vi.fn(),
    recordCorrect: vi.fn(),
    getErrorStreak: vi.fn().mockReturnValue(0),
    getCorrectStreak: vi.fn().mockReturnValue(0),
    shouldReduceDifficulty: vi.fn().mockReturnValue(false),
    checkStreakReward: vi.fn().mockReturnValue(false),
    clearStreak: vi.fn(),
    clearAll: vi.fn(),
  }
}

function createEngine(overrides: {
  classifier?: any
  policy?: any
  llmCoach?: any
  streakTracker?: ReturnType<typeof createStreakTracker>
  metrics?: any
  logger?: any
  now?: () => number
} = {}) {
  const classifier = overrides.classifier ?? {
    classify: vi.fn().mockResolvedValue({ trigger: 'error', priority: 2, errors: [] }),
  }
  const policy = overrides.policy ?? {
    shouldIntervene: vi.fn().mockResolvedValue(true),
    markIntervened: vi.fn().mockResolvedValue(undefined),
  }
  const llmCoach = overrides.llmCoach ?? {
    generate: vi.fn().mockResolvedValue(createResponse()),
  }
  const streakTracker = overrides.streakTracker ?? createStreakTracker()
  const metrics = overrides.metrics ?? { recordCall: vi.fn() }
  const logger = overrides.logger ?? { warn: vi.fn(), error: vi.fn() }

  return {
    engine: new CoachInterventionEngine({
      classifier,
      policy,
      llmCoach,
      streakTracker: streakTracker as never,
      metrics,
      logger,
      idGenerator: () => 'event-1',
      now: overrides.now ?? vi.fn()
        .mockReturnValueOnce(1000)
        .mockReturnValueOnce(1042)
        .mockReturnValue(2000),
    }),
    classifier,
    policy,
    llmCoach,
    streakTracker,
    metrics,
    logger,
  }
}

describe('CoachInterventionEngine', () => {
  it('classifier returns null → skipped/no_trigger without policy, LLM, metrics, or mark', async () => {
    const classifier = { classify: vi.fn().mockResolvedValue(null) }
    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(true),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }
    const llmCoach = { generate: vi.fn().mockResolvedValue(createResponse()) }
    const metrics = { recordCall: vi.fn() }
    const { engine } = createEngine({ classifier, policy, llmCoach, metrics })

    const decision = await engine.handle(makeDialogueInput())

    expect(decision).toEqual({ kind: 'skipped', reason: 'no_trigger' })
    expect(policy.shouldIntervene).not.toHaveBeenCalled()
    expect(policy.markIntervened).not.toHaveBeenCalled()
    expect(llmCoach.generate).not.toHaveBeenCalled()
    expect(metrics.recordCall).not.toHaveBeenCalled()
  })

  it('policy denies → skipped/cooldown_blocked without LLM, metrics, or mark', async () => {
    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(false),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }
    const llmCoach = { generate: vi.fn().mockResolvedValue(createResponse()) }
    const metrics = { recordCall: vi.fn() }
    const { engine } = createEngine({ policy, llmCoach, metrics })

    const decision = await engine.handle(makeDialogueInput())

    expect(decision).toEqual({ kind: 'skipped', reason: 'cooldown_blocked', trigger: 'error' })
    expect(policy.shouldIntervene).toHaveBeenCalledWith({ trigger: 'error', userId: 'user-1' })
    expect(policy.markIntervened).not.toHaveBeenCalled()
    expect(llmCoach.generate).not.toHaveBeenCalled()
    expect(metrics.recordCall).not.toHaveBeenCalled()
  })

  it('LLM success → intervention with metadata, metrics, and markIntervened', async () => {
    const response = createResponse({ text: '喵~ 差一点点！可以说：I am going' })
    const { engine, llmCoach, metrics, policy } = createEngine({
      llmCoach: { generate: vi.fn().mockResolvedValue(response) },
    })

    const decision = await engine.handle(makeDialogueInput())

    expect(decision.kind).toBe('intervention')
    if (decision.kind !== 'intervention') return
    expect(decision.intervention).toEqual({
      event_id: 'event-1',
      session_id: 'session-1',
      user_id: 'user-1',
      trigger: 'error',
      priority: 2,
      text: response.text,
      repeat_phrase: response.repeat_phrase,
      emotion: response.emotion,
      should_tts: response.should_tts,
      ttl_ms: response.ttl_ms,
      timestamp: 2000,
    })
    expect(decision.metadata).toEqual({
      trigger: 'error',
      fallback: false,
      tokenUsage: undefined,
      latencyMs: 42,
    })
    expect(llmCoach.generate).toHaveBeenCalledTimes(1)
    expect(metrics.recordCall).toHaveBeenCalledWith({
      trigger: 'error',
      latencyMs: 42,
      fallback: false,
      tokenUsage: undefined,
    })
    expect(policy.markIntervened).not.toHaveBeenCalled()
    await decision.commit()
    expect(policy.markIntervened).toHaveBeenCalledWith({ trigger: 'error', userId: 'user-1' })
  })

  it('generateWithUsage path records token usage in metadata and metrics', async () => {
    const tokenUsage = { promptTokens: 10, completionTokens: 5, totalTokens: 15 }
    const llmCoach = {
      generate: vi.fn(),
      generateWithUsage: vi.fn().mockResolvedValue({ response: createResponse(), tokenUsage }),
    }
    const { engine, metrics } = createEngine({ llmCoach })

    const decision = await engine.handle(makeDialogueInput())

    expect(llmCoach.generateWithUsage).toHaveBeenCalledTimes(1)
    expect(llmCoach.generate).not.toHaveBeenCalled()
    expect(decision.kind).toBe('intervention')
    if (decision.kind !== 'intervention') return
    expect(decision.metadata.tokenUsage).toEqual(tokenUsage)
    expect(metrics.recordCall).toHaveBeenCalledWith({
      trigger: 'error',
      latencyMs: 42,
      fallback: false,
      tokenUsage,
    })
  })

  it('LLM failure → fallback intervention and fallback metrics', async () => {
    const logger = { warn: vi.fn(), error: vi.fn() }
    const llmCoach = { generate: vi.fn().mockRejectedValue(new Error('LLM timeout')) }
    const { engine, metrics, policy } = createEngine({ llmCoach, logger })

    const decision = await engine.handle(makeDialogueInput())

    expect(decision.kind).toBe('intervention')
    if (decision.kind !== 'intervention') return
    expect(decision.intervention.text).toContain('再试一次')
    expect(decision.metadata.fallback).toBe(true)
    expect(logger.warn).toHaveBeenCalledWith('LLM coach failed, using fallback', {
      trigger: 'error',
      error: 'LLM timeout',
    })
    expect(metrics.recordCall).toHaveBeenCalledWith({
      trigger: 'error',
      latencyMs: 42,
      fallback: true,
      tokenUsage: undefined,
    })
    expect(policy.markIntervened).not.toHaveBeenCalled()
    await decision.commit()
    expect(policy.markIntervened).toHaveBeenCalledTimes(1)
  })

  it('error trigger records error before reading streak data and passing it to LLM', async () => {
    const streakTracker = createStreakTracker()
    streakTracker.getErrorStreak.mockReturnValue(2)
    streakTracker.getCorrectStreak.mockReturnValue(0)
    const llmCoach = { generate: vi.fn().mockResolvedValue(createResponse()) }
    const { engine } = createEngine({ streakTracker, llmCoach })

    await engine.handle(makeDialogueInput())

    expect(streakTracker.recordError).toHaveBeenCalledWith('user-1')
    expect(llmCoach.generate).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: 'user-1' }),
      'error',
      { error_streak: 2, correct_streak: 0 },
    )
  })

  it('wake and silence triggers do not record error or correct streak', async () => {
    const streakTracker = createStreakTracker()
    const wakeClassifier = { classify: vi.fn().mockResolvedValue({ trigger: 'wake', priority: 3, errors: [] }) }
    const { engine: wakeEngine } = createEngine({ classifier: wakeClassifier, streakTracker })

    await wakeEngine.handle(makeDialogueInput({ event_type: 'wake_request', player_text: 'help me' } as Partial<CoachInput>))

    expect(streakTracker.recordError).not.toHaveBeenCalled()
    expect(streakTracker.recordCorrect).not.toHaveBeenCalled()

    const silenceTracker = createStreakTracker()
    const silenceClassifier = { classify: vi.fn().mockResolvedValue({ trigger: 'silence', priority: 1, errors: [] }) }
    const { engine: silenceEngine } = createEngine({ classifier: silenceClassifier, streakTracker: silenceTracker })

    await silenceEngine.handle({
      event_type: 'silence_timeout',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      silence_ms: 15000,
      timestamp: 1779177600000,
      player_level: 'A1',
      recent_turns: [],
    })

    expect(silenceTracker.recordError).not.toHaveBeenCalled()
    expect(silenceTracker.recordCorrect).not.toHaveBeenCalled()
  })
})
