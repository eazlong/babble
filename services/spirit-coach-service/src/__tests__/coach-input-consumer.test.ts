import { describe, expect, it, vi } from 'vitest'
import { CoachInputConsumer } from '../workers/coach-input-consumer.js'
import { CoachSessionManager } from '../services/coach-session-manager.js'
import { ErrorDetector } from '../services/error-detector.js'
import { TriggerClassifier } from '../services/trigger-classifier.js'
import { InterventionPolicy } from '../services/intervention-policy.js'
import { CoachHintGenerator } from '../services/coach-hint-generator.js'

class FakeRedis {
  inputMessages = [
    [
      'coach.input',
      [
        [
          '1710000000-0',
          [
            'event_type', 'wake_request',
            'session_id', 'session-1',
            'user_id', 'user-1',
            'npc_id', 'npc-1',
            'player_text', 'help me',
            'timestamp', '1779177600000',
          ],
        ],
      ],
    ],
  ]
  added: Array<{ stream: string; values: Record<string, string> }> = []

  async xread() {
    return this.inputMessages
  }

  async xadd(stream: string, _id: string, ...pairs: string[]) {
    const values: Record<string, string> = {}
    for (let i = 0; i < pairs.length; i += 2) {
      values[pairs[i]] = pairs[i + 1]
    }
    this.added.push({ stream, values })
    return '1710000001-0'
  }

  async xdel() {
    return 1
  }

  async get() {
    return null
  }

  async set() {
    return 'OK'
  }
}

describe('CoachInputConsumer', () => {
  it('writes a wake intervention to coach.intervention', async () => {
    const redis = new FakeRedis()
    const policy = new InterventionPolicy(redis as never)
    const classifier = new TriggerClassifier(new ErrorDetector())
    const generator = new CoachHintGenerator()
    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(redis as never, classifier, policy, generator, sessionManager as never)
    await consumer.consumeOnce()

    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].stream).toBe('coach.intervention')
    expect(redis.added[0].values.trigger).toBe('wake')
    expect(sessionManager.push).toHaveBeenCalledTimes(1)
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
})
