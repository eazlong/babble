import { describe, expect, it, vi } from 'vitest'
import Fastify from 'fastify'
import { registerCoachRoutes } from '../routes/coach.js'

describe('POST /api/v1/coach/events', () => {
  it('serializes recent_turns array as JSON (not [object Object])', async () => {
    const xaddCalls: Array<{ stream: string; pairs: string[] }> = []

    const mockRedis = {
      async xadd(stream: string, ...args: unknown[]) {
        // args: '*', key1, val1, key2, val2, ...
        const pairs = args.slice(1) as string[]
        xaddCalls.push({ stream, pairs })
        return '1710000001-0'
      },
    }

    const app = Fastify()
    await registerCoachRoutes(app, mockRedis as any)

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/coach/events',
      payload: {
        event_type: 'dialogue_turn',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        player_text: 'I like cats',
        npc_response: 'Great!',
        language: 'en',
        timestamp: Date.now(),
        player_level: 'A1',
        recent_turns: [
          { speaker: 'player', text: 'hi' },
          { speaker: 'npc', text: 'hello' },
        ],
      },
    })

    expect(response.statusCode).toBe(202)
    expect(xaddCalls).toHaveLength(1)

    const { pairs } = xaddCalls[0]
    const recentTurnsIndex = pairs.indexOf('recent_turns')
    expect(recentTurnsIndex).toBeGreaterThan(-1)

    const serialized = pairs[recentTurnsIndex + 1]
    // Must NOT be "[object Object],[object Object]"
    expect(serialized).not.toContain('[object Object]')

    // Must be valid JSON that parses back to the original array
    const parsed = JSON.parse(serialized)
    expect(parsed).toEqual([
      { speaker: 'player', text: 'hi' },
      { speaker: 'npc', text: 'hello' },
    ])
  })

  it('serializes primitive fields as strings', async () => {
    const xaddCalls: Array<{ pairs: string[] }> = []

    const mockRedis = {
      async xadd(_stream: string, ...args: unknown[]) {
        xaddCalls.push({ pairs: args.slice(1) as string[] })
        return 'id'
      },
    }

    const app = Fastify()
    await registerCoachRoutes(app, mockRedis as any)

    await app.inject({
      method: 'POST',
      url: '/api/v1/coach/events',
      payload: {
        event_type: 'wake_request',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        player_text: 'help',
        timestamp: 1779177600000,
      },
    })

    const { pairs } = xaddCalls[0]
    // All values must be strings (no "[object Object]")
    for (let i = 1; i < pairs.length; i += 2) {
      expect(typeof pairs[i]).toBe('string')
      expect(pairs[i]).not.toContain('[object Object]')
    }
  })

  it('handles dialogue_turn without recent_turns (defaults to empty array)', async () => {
    const xaddCalls: Array<{ pairs: string[] }> = []

    const mockRedis = {
      async xadd(_stream: string, ...args: unknown[]) {
        xaddCalls.push({ pairs: args.slice(1) as string[] })
        return 'id'
      },
    }

    const app = Fastify()
    await registerCoachRoutes(app, mockRedis as any)

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/coach/events',
      payload: {
        event_type: 'dialogue_turn',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        player_text: 'hello',
        npc_response: 'hi',
        language: 'en',
        timestamp: Date.now(),
      },
    })

    expect(response.statusCode).toBe(202)

    const { pairs } = xaddCalls[0]
    const idx = pairs.indexOf('recent_turns')
    expect(idx).toBeGreaterThan(-1)
    // Default empty array should serialize to "[]"
    expect(pairs[idx + 1]).toBe('[]')
  })
})
