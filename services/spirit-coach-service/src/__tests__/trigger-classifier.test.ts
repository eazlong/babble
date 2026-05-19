import { beforeEach, describe, expect, it } from 'vitest'
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

import { ErrorDetector } from '../services/error-detector.js'
import { TriggerClassifier } from '../services/trigger-classifier.js'

describe('TriggerClassifier', () => {
  let classifier: TriggerClassifier

  beforeEach(() => {
    classifier = new TriggerClassifier(new ErrorDetector())
  })

  it('classifies wake requests as highest priority coach triggers', async () => {
    const result = await classifier.classify({
      event_type: 'wake_request',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      player_text: 'help me',
      timestamp: 1779177600000,
    })

    expect(result.trigger).toBe('wake')
    expect(result.priority).toBe(3)
  })

  it('classifies 15-second silence events as silence triggers', async () => {
    const result = await classifier.classify({
      event_type: 'silence_timeout',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      silence_ms: 15000,
      timestamp: 1779177600000,
    })

    expect(result.trigger).toBe('silence')
    expect(result.priority).toBe(1)
  })

  it('returns a high-severity error trigger for invalid grammar', async () => {
    const result = await classifier.classify({
      event_type: 'dialogue_turn',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      player_text: 'I am go to school',
      npc_response: 'Nice!',
      language: 'en',
      timestamp: 1779177600000,
    })

    expect(result.trigger).toBe('error')
    expect(result.errors[0].severity).toBe('high')
  })

  it('returns null when dialogue turn has no severe error', async () => {
    const result = await classifier.classify({
      event_type: 'dialogue_turn',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      player_text: 'I go to school',
      npc_response: 'Great!',
      language: 'en',
      timestamp: 1779177600000,
    })

    expect(result).toBeNull()
  })
})
