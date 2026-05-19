import { describe, expect, it } from 'vitest'
import {
  coachInputSchema,
  coachInterventionSchema,
  interventionPriority,
} from '../types/coach-events.js'

describe('coach event schemas', () => {
  it('accepts a silence timeout input payload', () => {
    const payload = coachInputSchema.parse({
      event_type: 'silence_timeout',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      silence_ms: 15000,
      timestamp: 1779177600000,
    })

    expect(payload.event_type).toBe('silence_timeout')
    expect(payload.silence_ms).toBe(15000)
  })

  it('accepts an intervention payload with priority metadata', () => {
    const payload = coachInterventionSchema.parse({
      event_id: 'coach-1',
      session_id: 'session-1',
      user_id: 'user-1',
      trigger: 'wake',
      priority: interventionPriority.wake,
      text: '我来帮你！你可以说：Can you help me?',
      repeat_phrase: 'Can you help me?',
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
      timestamp: 1779177600000,
    })

    expect(payload.trigger).toBe('wake')
    expect(payload.priority).toBe(3)
  })
})
