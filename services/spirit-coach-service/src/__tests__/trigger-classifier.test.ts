import { describe, expect, it } from 'vitest'
import { TriggerClassifier } from '../services/trigger-classifier.js'
import { coachInputSchema, coachInterventionSchema, interventionPriority } from '../types/coach-events.js'
import type { DetectedError, ErrorDetector } from '../services/error-detector.js'

// Mock ErrorDetector: create a mock implementation with controllable return values
function createMockErrorDetector(errors: DetectedError[] = []): ErrorDetector {
  return {
    analyze: async () => errors,
  } as unknown as ErrorDetector
}

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

describe('TriggerClassifier', () => {
  it('wake_request event → returns trigger: wake, priority 3, errors: []', async () => {
    const mockDetector = createMockErrorDetector()
    const classifier = new TriggerClassifier(mockDetector)

    const result = await classifier.classify({
      event_type: 'wake_request',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      player_text: 'help me',
      timestamp: 1779177600000,
    })

    expect(result).not.toBeNull()
    expect(result!.trigger).toBe('wake')
    expect(result!.priority).toBe(interventionPriority.wake)
    expect(result!.errors).toEqual([])
  })

  it('silence_timeout event → returns trigger: silence, priority 1, errors: []', async () => {
    const mockDetector = createMockErrorDetector()
    const classifier = new TriggerClassifier(mockDetector)

    const result = await classifier.classify({
      event_type: 'silence_timeout',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      silence_ms: 15000,
      timestamp: 1779177600000,
    })

    expect(result).not.toBeNull()
    expect(result!.trigger).toBe('silence')
    expect(result!.priority).toBe(interventionPriority.silence)
    expect(result!.errors).toEqual([])
  })

  it('dialogue_turn event (no errors) → ErrorDetector returns empty → classify returns null', async () => {
    const mockDetector = createMockErrorDetector([])
    const classifier = new TriggerClassifier(mockDetector)

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

  it('dialogue_turn event (high severity errors) → trigger: error, priority 2, includes error list', async () => {
    const highSeverityErrors: DetectedError[] = [
      {
        type: 'grammar',
        severity: 'high',
        original_text: 'I am go',
        correction: 'I am going',
        explanation: 'Use present continuous.',
      },
    ]
    const mockDetector = createMockErrorDetector(highSeverityErrors)
    const classifier = new TriggerClassifier(mockDetector)

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

    expect(result).not.toBeNull()
    expect(result!.trigger).toBe('error')
    expect(result!.priority).toBe(interventionPriority.error)
    expect(result!.errors).toHaveLength(1)
    expect(result!.errors[0]).toEqual({
      type: 'grammar',
      severity: 'high',
      original_text: 'I am go',
      correction: 'I am going',
      explanation: 'Use present continuous.',
    })
  })

  it('dialogue_turn event (only low severity errors) → filters to high only, returns null', async () => {
    const lowSeverityErrors: DetectedError[] = [
      {
        type: 'vocabulary',
        severity: 'low',
        original_text: 'bigly',
        correction: 'greatly',
        explanation: 'Use a more standard word.',
      },
    ]
    const mockDetector = createMockErrorDetector(lowSeverityErrors)
    const classifier = new TriggerClassifier(mockDetector)

    const result = await classifier.classify({
      event_type: 'dialogue_turn',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      player_text: 'I am bigly happy',
      npc_response: 'OK!',
      language: 'en',
      timestamp: 1779177600000,
    })

    expect(result).toBeNull()
  })
})
