import { describe, expect, it, vi } from 'vitest'
import { CoachInputConsumer } from '../workers/coach-input-consumer.js'
import { CoachSessionManager } from '../services/coach-session-manager.js'

// Helper: create a dialogue_turn message in the format returned by xread
function makeDialogueTurnMessage(overrides: Record<string, string> = {}) {
  const fields: string[] = [
    'event_type', overrides.event_type ?? 'dialogue_turn',
    'session_id', overrides.session_id ?? 'session-1',
    'user_id', overrides.user_id ?? 'user-1',
    'npc_id', overrides.npc_id ?? 'npc-1',
    'player_text', overrides.player_text ?? 'I go to school',
    'npc_response', overrides.npc_response ?? 'Great!',
    'language', overrides.language ?? 'en',
    'timestamp', overrides.timestamp ?? '1779177600000',
  ]
  return ['1710000000-0', fields] as [string, string[]]
}

// Mock Redis that tracks all calls
function createMockRedis(inputMessages?: [string, [string, string[]][]][]) {
  const calls = {
    xread: [] as unknown[][],
    xadd: [] as unknown[][],
    xdel: [] as [string, string][],
    get: [] as string[],
    set: [] as unknown[][],
  }

  const added: Array<{ stream: string; values: Record<string, string> }> = []
  const deleted: string[] = []
  const cooldownStore = new Map<string, string>()

  return {
    added,
    deleted,
    calls,
    cooldownStore,

    preSetCooldown(key: string, value: string) {
      cooldownStore.set(key, value)
    },

    async xread(...args: unknown[]): Promise<[string, [string, string[]][]][] | null> {
      calls.xread.push(args)
      return inputMessages ?? null
    },

    async xadd(...args: unknown[]): Promise<string> {
      calls.xadd.push(args)
      const stream = args[0] as string
      const pairsStart = 5
      const pairs = args.slice(pairsStart)

      const values: Record<string, string> = {}
      for (let i = 0; i < pairs.length; i += 2) {
        values[pairs[i] as string] = String(pairs[i + 1])
      }

      added.push({ stream, values })
      return '1710000001-0'
    },

    async xdel(stream: string, id: string): Promise<number> {
      calls.xdel.push([stream, id])
      deleted.push(id)
      return 1
    },

    async get(key: string): Promise<string | null> {
      calls.get.push(key)
      return cooldownStore.get(key) ?? null
    },

    async set(key: string, value: string, mode?: string, ttl?: number): Promise<string> {
      calls.set.push([key, value, mode, ttl])
      cooldownStore.set(key, value)
      return 'OK'
    },
  }
}

function createMockLLMCoach(response?: object) {
  return {
    generate: vi.fn().mockResolvedValue(response ?? {
      text: '喵~ 差一点点！可以说：I am going',
      repeat_phrase: 'I am going',
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
    }),
  }
}

function createFailingLLMCoach() {
  return {
    generate: vi.fn().mockRejectedValue(new Error('LLM timeout')),
  }
}

const mockLogger = {
  warn: vi.fn(),
  error: vi.fn(),
}

describe('CoachInputConsumer', () => {
  it('classify returns null → xdel deletes message, does not call push', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage()]],
    ])

    const classifier = { classify: vi.fn().mockResolvedValue(null) }
    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(true),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }
    const llmCoach = createMockLLMCoach()
    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      llmCoach as never, sessionManager as never, mockLogger as never,
    )

    await consumer.consumeOnce()

    expect(classifier.classify).toHaveBeenCalledTimes(1)
    expect(redis.calls.xdel).toHaveLength(1)
    expect(redis.calls.xdel[0]).toEqual(['coach.input', '1710000000-0'])
    expect(policy.shouldIntervene).not.toHaveBeenCalled()
    expect(sessionManager.push).not.toHaveBeenCalled()
    expect(redis.added).toHaveLength(0)
  })

  it('shouldIntervene returns false → xdel deletes message, does not call LLM', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage({ player_text: 'I am go to school' })]],
    ])

    const classifier = {
      classify: vi.fn().mockResolvedValue({
        trigger: 'error',
        priority: 2,
        input: {},
        errors: [{ type: 'grammar', severity: 'high', original_text: 'I am go', correction: 'I am going', explanation: '...' }],
      }),
    }

    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(false),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }

    const llmCoach = createMockLLMCoach()
    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      llmCoach as never, sessionManager as never, mockLogger as never,
    )

    await consumer.consumeOnce()

    expect(classifier.classify).toHaveBeenCalledTimes(1)
    expect(policy.shouldIntervene).toHaveBeenCalledTimes(1)
    expect(redis.calls.xdel).toHaveLength(1)
    expect(llmCoach.generate).not.toHaveBeenCalled()
    expect(sessionManager.push).not.toHaveBeenCalled()
    expect(redis.added).toHaveLength(0)
  })

  it('full pipeline: classifier → policy → LLM → xadd → markIntervened → push → xdel', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage({ player_text: 'I am go to school' })]],
    ])

    const classifier = {
      classify: vi.fn().mockResolvedValue({
        trigger: 'error',
        priority: 2,
        input: {},
        errors: [{
          type: 'grammar' as const,
          severity: 'high' as const,
          original_text: 'I am go',
          correction: 'I am going',
          explanation: 'Use present continuous.',
        }],
      }),
    }

    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(true),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }

    const llmCoach = createMockLLMCoach({
      text: '喵~ 差一点点！可以说：I am going',
      repeat_phrase: 'I am going',
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
    })

    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      llmCoach as never, sessionManager as never, mockLogger as never,
    )

    await consumer.consumeOnce()

    expect(classifier.classify).toHaveBeenCalledTimes(1)
    expect(policy.shouldIntervene).toHaveBeenCalledTimes(1)
    expect(policy.shouldIntervene).toHaveBeenCalledWith({ trigger: 'error', userId: 'user-1' })

    expect(llmCoach.generate).toHaveBeenCalledTimes(1)
    const [input, trigger] = (llmCoach.generate as any).mock.calls[0]
    expect(trigger).toBe('error')
    expect(input.player_text).toBe('I am go to school')

    expect(redis.calls.xadd).toHaveLength(1)
    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].stream).toBe('coach.intervention')

    expect(policy.markIntervened).toHaveBeenCalledTimes(1)
    expect(policy.markIntervened).toHaveBeenCalledWith({ trigger: 'error', userId: 'user-1' })

    expect(sessionManager.push).toHaveBeenCalledTimes(1)
    expect(redis.calls.xdel).toHaveLength(1)
    expect(redis.calls.xdel[0]).toEqual(['coach.input', '1710000000-0'])

    const payload = redis.added[0].values
    expect(payload.event_id).toBeDefined()
    expect(payload.event_id).toHaveLength(36)
    expect(payload.session_id).toBe('session-1')
    expect(payload.user_id).toBe('user-1')
    expect(payload.trigger).toBe('error')
    expect(payload.priority).toBe('2')
    expect(payload.text).toContain('I am going')
    expect(payload.repeat_phrase).toBe('I am going')
    expect(payload.emotion).toBe('encourage')
    expect(payload.should_tts).toBe('true')
    expect(payload.ttl_ms).toBe('8000')
  })

  it('LLM failure → uses fallback template', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage({ player_text: 'I am go to school' })]],
    ])

    const classifier = {
      classify: vi.fn().mockResolvedValue({
        trigger: 'error',
        priority: 2,
        input: {},
        errors: [],
      }),
    }

    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(true),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }

    const llmCoach = createFailingLLMCoach()
    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      llmCoach as never, sessionManager as never, mockLogger as never,
    )

    await consumer.consumeOnce()

    // LLM was called and failed
    expect(llmCoach.generate).toHaveBeenCalledTimes(1)

    // Logger warned about failure
    expect(mockLogger.warn).toHaveBeenCalled()

    // But intervention was still produced via fallback
    expect(redis.added).toHaveLength(1)
    const payload = redis.added[0].values
    expect(payload.trigger).toBe('error')
    expect(payload.text).toContain('再试一次') // fallback error text
    expect(payload.emotion).toBe('encourage')

    // Pipeline completed normally
    expect(sessionManager.push).toHaveBeenCalledTimes(1)
    expect(policy.markIntervened).toHaveBeenCalledTimes(1)
    expect(redis.calls.xdel).toHaveLength(1)
  })

  it('handles wake_request trigger with LLM', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage({
        event_type: 'wake_request',
        player_text: 'help me',
      })]],
    ])

    const classifier = {
      classify: vi.fn().mockResolvedValue({
        trigger: 'wake',
        priority: 3,
        input: {},
        errors: [],
      }),
    }

    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(true),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }

    const llmCoach = createMockLLMCoach({
      text: '喵~ 小飞猫来啦！我可以帮你。',
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
    })

    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      llmCoach as never, sessionManager as never, mockLogger as never,
    )

    await consumer.consumeOnce()

    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].values.trigger).toBe('wake')
    expect(redis.added[0].values.priority).toBe('3')
    expect(sessionManager.push).toHaveBeenCalledTimes(1)
  })

  it('handles silence_timeout trigger with LLM', async () => {
    const silenceFields: string[] = [
      'event_type', 'silence_timeout',
      'session_id', 'session-1',
      'user_id', 'user-1',
      'npc_id', 'npc-1',
      'silence_ms', '15000',
      'timestamp', '1779177600000',
    ]

    const redis = createMockRedis([
      ['coach.input', [['1710000000-0', silenceFields] as [string, string[]]]],
    ])

    const classifier = {
      classify: vi.fn().mockResolvedValue({
        trigger: 'silence',
        priority: 1,
        input: {},
        errors: [],
      }),
    }

    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(true),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }

    const llmCoach = createMockLLMCoach({
      text: '喵~ 想不出来也没关系，可以试试说：I need help.',
      repeat_phrase: 'I need help.',
      emotion: 'neutral',
      should_tts: true,
      ttl_ms: 8000,
    })

    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      llmCoach as never, sessionManager as never, mockLogger as never,
    )

    await consumer.consumeOnce()

    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].values.trigger).toBe('silence')
    expect(redis.added[0].values.priority).toBe('1')
  })

  it('parses player_level and recent_turns from Redis stream', async () => {
    const fields: string[] = [
      'event_type', 'dialogue_turn',
      'session_id', 'session-1',
      'user_id', 'user-1',
      'npc_id', 'npc-1',
      'player_text', 'I like cats',
      'npc_response', 'Great!',
      'language', 'en',
      'timestamp', '1779177600000',
      'player_level', 'B2',
      'recent_turns', JSON.stringify([
        { speaker: 'player', text: 'hi' },
        { speaker: 'npc', text: 'hello' },
      ]),
    ]

    const redis = createMockRedis([
      ['coach.input', [['1710000000-0', fields] as [string, string[]]]],
    ])

    const classifier = {
      classify: vi.fn().mockResolvedValue({
        trigger: 'error',
        priority: 2,
        input: {},
        errors: [{ type: 'grammar', severity: 'high' }],
      }),
    }

    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(true),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }

    const llmCoach = createMockLLMCoach()
    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      llmCoach as never, sessionManager as never, mockLogger as never,
    )

    await consumer.consumeOnce()

    expect(llmCoach.generate).toHaveBeenCalledTimes(1)
    const [input, trigger] = (llmCoach.generate as any).mock.calls[0]
    expect(trigger).toBe('error')
    expect(input.player_level).toBe('B2')
    expect(input.recent_turns).toEqual([
      { speaker: 'player', text: 'hi' },
      { speaker: 'npc', text: 'hello' },
    ])
  })

  it('xread returns null → no operations performed', async () => {
    const redis = createMockRedis(null)
    const classifier = { classify: vi.fn() }
    const policy = { shouldIntervene: vi.fn(), markIntervened: vi.fn() }
    const llmCoach = createMockLLMCoach()
    const sessionManager = { push: vi.fn() }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      llmCoach as never, sessionManager as never, mockLogger as never,
    )

    await consumer.consumeOnce()

    expect(classifier.classify).not.toHaveBeenCalled()
    expect(policy.shouldIntervene).not.toHaveBeenCalled()
    expect(sessionManager.push).not.toHaveBeenCalled()
    expect(redis.added).toHaveLength(0)
  })
})

describe('CoachSessionManager', () => {
  it('pushes payloads to the matching session connection', async () => {
    const sent: string[] = []
    const socket = { send: vi.fn((message: string) => sent.push(message)) }
    const manager = new CoachSessionManager()

    manager.attach('session-1', socket as never)
    await manager.push('session-1', { trigger: 'wake', text: 'hello' })

    expect(socket.send).toHaveBeenCalledTimes(1)
    expect(sent[0]).toContain('wake')
  })

  it('does nothing when session is not attached', async () => {
    const manager = new CoachSessionManager()
    await expect(manager.push('nonexistent', { trigger: 'wake' })).resolves.toBeUndefined()
  })
})
