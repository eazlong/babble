import { describe, expect, it, vi } from 'vitest'
import { CoachInputConsumer } from '../workers/coach-input-consumer.js'
import { CoachSessionManager } from '../services/coach-session-manager.js'
import type { CoachIntervention } from '../types/coach-events.js'

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
  if (overrides.player_level !== undefined) {
    fields.push('player_level', overrides.player_level)
  }
  if (overrides.recent_turns !== undefined) {
    fields.push('recent_turns', overrides.recent_turns)
  }
  return ['1710000000-0', fields] as [string, string[]]
}

function makeIntervention(overrides: Partial<CoachIntervention> = {}): CoachIntervention {
  return {
    event_id: 'event-1',
    session_id: 'session-1',
    user_id: 'user-1',
    trigger: 'error',
    priority: 2,
    text: '喵~ 差一点点！可以说：I am going',
    repeat_phrase: 'I am going',
    emotion: 'encourage',
    should_tts: true,
    ttl_ms: 8000,
    timestamp: 1779177600100,
    ...overrides,
  }
}

function createMockRedis(inputMessages?: [string, [string, string[]][]][] | null) {
  const calls = {
    xread: [] as unknown[][],
    xadd: [] as unknown[][],
    xdel: [] as [string, string][],
  }

  const added: Array<{ stream: string; values: Record<string, string> }> = []
  const deleted: string[] = []

  return {
    added,
    deleted,
    calls,

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
  }
}

function createEngine(decision: any) {
  const resolvedDecision = decision.kind === 'intervention'
    ? { ...decision, commit: decision.commit ?? vi.fn().mockResolvedValue(undefined) }
    : decision
  return { handle: vi.fn().mockResolvedValue(resolvedDecision) }
}

describe('CoachInputConsumer', () => {
  it('xread returns null → no operations performed', async () => {
    const redis = createMockRedis(null)
    const engine = createEngine({ kind: 'skipped', reason: 'no_trigger' })
    const sessionManager = { push: vi.fn() }
    const consumer = new CoachInputConsumer(redis as never, engine, sessionManager)

    await consumer.consumeOnce()

    expect(engine.handle).not.toHaveBeenCalled()
    expect(sessionManager.push).not.toHaveBeenCalled()
    expect(redis.added).toHaveLength(0)
    expect(redis.calls.xdel).toHaveLength(0)
  })

  it('skipped decision → xdel deletes message and does not publish or push', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage()]],
    ])
    const engine = createEngine({ kind: 'skipped', reason: 'no_trigger' })
    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }
    const consumer = new CoachInputConsumer(redis as never, engine, sessionManager)

    await consumer.consumeOnce()

    expect(engine.handle).toHaveBeenCalledTimes(1)
    expect(redis.calls.xdel).toEqual([['coach.input', '1710000000-0']])
    expect(sessionManager.push).not.toHaveBeenCalled()
    expect(redis.added).toHaveLength(0)
  })

  it('intervention decision → xadd, push, and xdel', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage({ player_text: 'I am go to school' })]],
    ])
    const intervention = makeIntervention()
    const engine = createEngine({
      kind: 'intervention',
      intervention,
      metadata: { trigger: 'error', fallback: false, latencyMs: 10 },
    })
    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }
    const consumer = new CoachInputConsumer(redis as never, engine, sessionManager)

    await consumer.consumeOnce()

    expect(engine.handle).toHaveBeenCalledTimes(1)
    expect(redis.calls.xadd).toHaveLength(1)
    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].stream).toBe('coach.intervention')
    expect((await engine.handle.mock.results[0].value).commit).toHaveBeenCalledTimes(1)
    expect(sessionManager.push).toHaveBeenCalledWith('session-1', intervention)
    expect(redis.calls.xdel).toEqual([['coach.input', '1710000000-0']])

    const payload = redis.added[0].values
    expect(payload.event_id).toBe('event-1')
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

  it('filters undefined intervention fields before xadd', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage()]],
    ])
    const intervention = makeIntervention({ repeat_phrase: undefined })
    const engine = createEngine({
      kind: 'intervention',
      intervention,
      metadata: { trigger: 'error', fallback: false, latencyMs: 10 },
    })
    const consumer = new CoachInputConsumer(redis as never, engine, { push: vi.fn().mockResolvedValue(undefined) })

    await consumer.consumeOnce()

    expect(redis.added[0].values.repeat_phrase).toBeUndefined()
  })

  it('parses player_level and recent_turns from Redis stream before calling engine', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage({
        player_level: 'B2',
        recent_turns: JSON.stringify([
          { speaker: 'player', text: 'hi' },
          { speaker: 'npc', text: 'hello' },
        ]),
      })]],
    ])
    const engine = createEngine({ kind: 'skipped', reason: 'no_trigger' })
    const consumer = new CoachInputConsumer(redis as never, engine, { push: vi.fn().mockResolvedValue(undefined) })

    await consumer.consumeOnce()

    expect(engine.handle).toHaveBeenCalledWith(expect.objectContaining({
      player_level: 'B2',
      recent_turns: [
        { speaker: 'player', text: 'hi' },
        { speaker: 'npc', text: 'hello' },
      ],
    }))
  })

  it('malformed recent_turns falls back to empty array', async () => {
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurnMessage({ recent_turns: 'not-json' })]],
    ])
    const engine = createEngine({ kind: 'skipped', reason: 'no_trigger' })
    const consumer = new CoachInputConsumer(redis as never, engine, { push: vi.fn().mockResolvedValue(undefined) })

    await consumer.consumeOnce()

    expect(engine.handle).toHaveBeenCalledWith(expect.objectContaining({
      recent_turns: [],
    }))
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
