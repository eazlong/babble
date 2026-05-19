import { describe, expect, it } from 'vitest'
import { CoachPublisher } from '../services/coach-publisher.js'

class FakeRedis {
  calls: Array<{ stream: string; pairs: string[] }> = []

  async xadd(stream: string, _id: string, ...pairs: string[]) {
    this.calls.push({ stream, pairs })
    return '1710000001-0'
  }
}

describe('CoachPublisher', () => {
  it('publishes dialogue_turn events to coach.input', async () => {
    const redis = new FakeRedis()
    const publisher = new CoachPublisher(redis as never)

    await publisher.publishDialogueTurn({
      session_id: 'session-1',
      user_id: 'anonymous',
      npc_id: 'npc-1',
      player_text: 'I am go to school',
      npc_response: 'Nice try!',
      language: 'en',
      timestamp: 1779177600000,
    })

    expect(redis.calls).toHaveLength(1)
    expect(redis.calls[0].stream).toBe('coach.input')
    expect(redis.calls[0].pairs).toContain('event_type')
    expect(redis.calls[0].pairs).toContain('dialogue_turn')
  })
})
