import { describe, expect, it } from 'vitest'
import { coachInputSchema } from '../types/coach-events.js'

describe('coach.input schema extension', () => {
  describe('player_level', () => {
    it('accepts valid player_level values', () => {
      for (const level of ['A1', 'A2', 'B1', 'B2'] as const) {
        const result = coachInputSchema.parse({
          event_type: 'dialogue_turn',
          session_id: 's1',
          user_id: 'u1',
          npc_id: 'n1',
          player_text: 'hello',
          npc_response: 'hi',
          language: 'en',
          timestamp: Date.now(),
          player_level: level,
        })
        expect(result.player_level).toBe(level)
      }
    })

    it('defaults player_level to A1 when omitted', () => {
      const result = coachInputSchema.parse({
        event_type: 'dialogue_turn',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        player_text: 'hello',
        npc_response: 'hi',
        language: 'en',
        timestamp: Date.now(),
      })
      expect(result.player_level).toBe('A1')
    })

    it('rejects invalid player_level values', () => {
      expect(() =>
        coachInputSchema.parse({
          event_type: 'dialogue_turn',
          session_id: 's1',
          user_id: 'u1',
          npc_id: 'n1',
          player_text: 'hello',
          npc_response: 'hi',
          language: 'en',
          timestamp: Date.now(),
          player_level: 'C1',
        })
      ).toThrow()
    })
  })

  describe('recent_turns', () => {
    it('accepts valid recent_turns', () => {
      const result = coachInputSchema.parse({
        event_type: 'dialogue_turn',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        player_text: 'hello',
        npc_response: 'hi',
        language: 'en',
        timestamp: Date.now(),
        recent_turns: [
          { speaker: 'player', text: 'hi' },
          { speaker: 'npc', text: 'hello' },
        ],
      })
      expect(result.recent_turns).toEqual([
        { speaker: 'player', text: 'hi' },
        { speaker: 'npc', text: 'hello' },
      ])
    })

    it('defaults recent_turns to empty array when omitted', () => {
      const result = coachInputSchema.parse({
        event_type: 'dialogue_turn',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        player_text: 'hello',
        npc_response: 'hi',
        language: 'en',
        timestamp: Date.now(),
      })
      expect(result.recent_turns).toEqual([])
    })

    it('rejects invalid speaker values', () => {
      expect(() =>
        coachInputSchema.parse({
          event_type: 'dialogue_turn',
          session_id: 's1',
          user_id: 'u1',
          npc_id: 'n1',
          player_text: 'hello',
          npc_response: 'hi',
          language: 'en',
          timestamp: Date.now(),
          recent_turns: [{ speaker: 'system', text: 'hi' }],
        })
      ).toThrow()
    })
  })

  describe('backward compatibility', () => {
    it('parses dialogue_turn without new fields', () => {
      const result = coachInputSchema.parse({
        event_type: 'dialogue_turn',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        player_text: 'hello',
        npc_response: 'hi',
        language: 'en',
        timestamp: Date.now(),
      })
      expect(result.event_type).toBe('dialogue_turn')
      expect(result.player_level).toBe('A1')
      expect(result.recent_turns).toEqual([])
    })

    it('parses wake_request without new fields', () => {
      const result = coachInputSchema.parse({
        event_type: 'wake_request',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        player_text: 'help',
        timestamp: Date.now(),
      })
      expect(result.event_type).toBe('wake_request')
      expect(result.player_level).toBe('A1')
      expect(result.recent_turns).toEqual([])
    })

    it('parses silence_timeout without new fields', () => {
      const result = coachInputSchema.parse({
        event_type: 'silence_timeout',
        session_id: 's1',
        user_id: 'u1',
        npc_id: 'n1',
        silence_ms: 15000,
        timestamp: Date.now(),
      })
      expect(result.event_type).toBe('silence_timeout')
      expect(result.player_level).toBe('A1')
      expect(result.recent_turns).toEqual([])
    })
  })
})
