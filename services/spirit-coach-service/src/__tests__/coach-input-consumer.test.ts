import { describe, expect, it, vi } from 'vitest'
import { CoachInputConsumer } from '../workers/coach-input-consumer.js'
import { CoachSessionManager } from '../services/coach-session-manager.js'
import type { DetectedError } from '../services/error-detector.js'

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
    // Expose for assertions
    added,
    deleted,
    calls,
    cooldownStore,

    // Set up cooldown state
    preSetCooldown(key: string, value: string) {
      cooldownStore.set(key, value)
    },

    async xread(...args: unknown[]): Promise<[string, [string, string[]][]][] | null> {
      calls.xread.push(args)
      return inputMessages ?? null
    },

    async xadd(...args: unknown[]): Promise<string> {
      calls.xadd.push(args)

      // Consumer calls: xadd('coach.intervention', 'MAXLEN', '~', '10000', '*', key1, val1, ...)
      // So the actual key-value pairs start after the 5th argument
      const stream = args[0] as string
      const pairsStart = 5 // skip stream, MAXLEN, ~, 10000, *
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

describe('CoachInputConsumer', () => {
  it('classify returns null → xdel deletes message, does not call push', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage()]],
    ])

    // Mock classifier that returns null (no errors)
    const classifier = {
      classify: vi.fn().mockResolvedValue(null),
    }

    // Mock policy
    const policy = {
      shouldIntervene: vi.fn().mockResolvedValue(true),
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }

    // Mock generator
    const generator = {
      generate: vi.fn().mockReturnValue({
        text: 'hint',
        emotion: 'neutral',
        should_tts: true,
        ttl_ms: 8000,
      }),
    }

    // Mock session manager
    const sessionManager = {
      push: vi.fn().mockResolvedValue(undefined),
    }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      generator as never, sessionManager as never,
    )

    await consumer.consumeOnce()

    // classifier.classify was called
    expect(classifier.classify).toHaveBeenCalledTimes(1)

    // xdel was called to delete the message
    expect(redis.calls.xdel).toHaveLength(1)
    expect(redis.calls.xdel[0]).toEqual(['coach.input', '1710000000-0'])

    // shouldIntervene was NOT called (early return on null)
    expect(policy.shouldIntervene).not.toHaveBeenCalled()

    // sessionManager.push was NOT called
    expect(sessionManager.push).not.toHaveBeenCalled()

    // No intervention was added
    expect(redis.added).toHaveLength(0)
  })

  it('classify returns non-null, shouldIntervene returns false → xdel deletes message, does not push', async () => {
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
      shouldIntervene: vi.fn().mockResolvedValue(false), // blocked by cooldown
      markIntervened: vi.fn().mockResolvedValue(undefined),
    }

    const generator = {
      generate: vi.fn().mockReturnValue({
        text: 'hint',
        emotion: 'neutral',
        should_tts: true,
        ttl_ms: 8000,
      }),
    }

    const sessionManager = {
      push: vi.fn().mockResolvedValue(undefined),
    }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      generator as never, sessionManager as never,
    )

    await consumer.consumeOnce()

    // classifier was called
    expect(classifier.classify).toHaveBeenCalledTimes(1)

    // shouldIntervene was called
    expect(policy.shouldIntervene).toHaveBeenCalledTimes(1)
    expect(policy.shouldIntervene).toHaveBeenCalledWith({
      trigger: 'error',
      userId: 'user-1',
    })

    // xdel was called to delete the message (cooldown blocked)
    expect(redis.calls.xdel).toHaveLength(1)

    // generator.generate was NOT called
    expect(generator.generate).not.toHaveBeenCalled()

    // sessionManager.push was NOT called
    expect(sessionManager.push).not.toHaveBeenCalled()

    // No intervention was added
    expect(redis.added).toHaveLength(0)
  })

  it('classify returns non-null, shouldIntervene returns true → full pipeline: xadd, markIntervened, push, xdel', async () => {
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

    const generator = {
      generate: vi.fn().mockReturnValue({
        text: '差一点点！可以说：I am going',
        repeat_phrase: 'I am going',
        emotion: 'encourage',
        should_tts: true,
        ttl_ms: 8000,
      }),
    }

    const sessionManager = {
      push: vi.fn().mockResolvedValue(undefined),
    }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      generator as never, sessionManager as never,
    )

    await consumer.consumeOnce()

    // 1. classifier.classify was called
    expect(classifier.classify).toHaveBeenCalledTimes(1)

    // 2. shouldIntervene was called
    expect(policy.shouldIntervene).toHaveBeenCalledTimes(1)
    expect(policy.shouldIntervene).toHaveBeenCalledWith({
      trigger: 'error',
      userId: 'user-1',
    })

    // 3. generator.generate was called
    expect(generator.generate).toHaveBeenCalledTimes(1)
    expect(generator.generate).toHaveBeenCalledWith({
      trigger: 'error',
      errors: expect.any(Array),
    })

    // 4. xadd was called with coach.intervention
    expect(redis.calls.xadd).toHaveLength(1)
    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].stream).toBe('coach.intervention')

    // 5. markIntervened was called
    expect(policy.markIntervened).toHaveBeenCalledTimes(1)
    expect(policy.markIntervened).toHaveBeenCalledWith({
      trigger: 'error',
      userId: 'user-1',
    })

    // 6. sessionManager.push was called
    expect(sessionManager.push).toHaveBeenCalledTimes(1)

    // 7. xdel was called to clean up the input message
    expect(redis.calls.xdel).toHaveLength(1)
    expect(redis.calls.xdel[0]).toEqual(['coach.input', '1710000000-0'])

    // Verify payload format
    const payload = redis.added[0].values
    expect(payload.event_id).toBeDefined()
    expect(payload.event_id).toHaveLength(36) // UUID
    expect(payload.session_id).toBe('session-1')
    expect(payload.user_id).toBe('user-1')
    expect(payload.trigger).toBe('error')
    expect(payload.priority).toBe('2')
    expect(payload.text).toContain('I am going')
    expect(payload.repeat_phrase).toBe('I am going')
    expect(payload.emotion).toBe('encourage')
    expect(payload.should_tts).toBe('true')
    expect(payload.ttl_ms).toBe('8000')
    expect(payload.timestamp).toBeDefined()
  })

  it('handles wake_request trigger through full pipeline', async () => {
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

    const generator = {
      generate: vi.fn().mockReturnValue({
        text: '我来帮你！你可以说：Can you help me?',
        repeat_phrase: 'Can you help me?',
        emotion: 'encourage',
        should_tts: true,
        ttl_ms: 8000,
      }),
    }

    const sessionManager = {
      push: vi.fn().mockResolvedValue(undefined),
    }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      generator as never, sessionManager as never,
    )

    await consumer.consumeOnce()

    // Full pipeline executed
    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].values.trigger).toBe('wake')
    expect(redis.added[0].values.priority).toBe('3')
    expect(redis.added[0].values.repeat_phrase).toBe('Can you help me?')
    expect(sessionManager.push).toHaveBeenCalledTimes(1)
    expect(policy.markIntervened).toHaveBeenCalledWith({ trigger: 'wake', userId: 'user-1' })
    expect(redis.calls.xdel).toHaveLength(1)
  })

  it('handles silence_timeout trigger through full pipeline', async () => {
    // Need to use silence_timeout specific fields
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

    const generator = {
      generate: vi.fn().mockReturnValue({
        text: '想不出来也没关系，可以试试说：I need help.',
        repeat_phrase: 'I need help.',
        emotion: 'neutral',
        should_tts: true,
        ttl_ms: 8000,
      }),
    }

    const sessionManager = {
      push: vi.fn().mockResolvedValue(undefined),
    }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      generator as never, sessionManager as never,
    )

    await consumer.consumeOnce()

    // Full pipeline executed
    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].values.trigger).toBe('silence')
    expect(redis.added[0].values.priority).toBe('1')
    expect(sessionManager.push).toHaveBeenCalledTimes(1)
    expect(policy.markIntervened).toHaveBeenCalledWith({ trigger: 'silence', userId: 'user-1' })
    expect(redis.calls.xdel).toHaveLength(1)
  })

  it('xread returns null → no operations performed', async () => {
    const redis = createMockRedis(null) // null means no messages

    const classifier = { classify: vi.fn() }
    const policy = { shouldIntervene: vi.fn(), markIntervened: vi.fn() }
    const generator = { generate: vi.fn() }
    const sessionManager = { push: vi.fn() }

    const consumer = new CoachInputConsumer(
      redis as never, classifier as never, policy as never,
      generator as never, sessionManager as never,
    )

    await consumer.consumeOnce()

    // Nothing should be called
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
    // No session attached; push should not throw
    await expect(manager.push('nonexistent', { trigger: 'wake' })).resolves.toBeUndefined()
  })
})
