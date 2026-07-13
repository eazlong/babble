import { describe, expect, it } from 'vitest'
import { getFallback, FALLBACK_TEMPLATES } from '../services/fallback-templates.js'
import { coachResponseSchema } from '../types/coach-events.js'

describe('fallback-templates', () => {
  it('has a fallback for each trigger', () => {
    expect(FALLBACK_TEMPLATES.wake).toBeDefined()
    expect(FALLBACK_TEMPLATES.silence).toBeDefined()
    expect(FALLBACK_TEMPLATES.error).toBeDefined()
  })

  it('all fallback responses pass the CoachResponse schema', () => {
    for (const trigger of ['wake', 'silence', 'error'] as const) {
      const result = coachResponseSchema.safeParse(FALLBACK_TEMPLATES[trigger])
      expect(result.success, `fallback for ${trigger} should be valid`).toBe(true)
    }
  })

  it('getFallback returns a copy (not the original)', () => {
    const a = getFallback('wake')
    const b = getFallback('wake')
    expect(a).toEqual(b)
    expect(a).not.toBe(b)
  })

  it('wake fallback mentions 小飞猫', () => {
    expect(getFallback('wake').text).toContain('小飞猫')
  })

  it('silence fallback provides a suggestion', () => {
    const fb = getFallback('silence')
    expect(fb.text).toContain('试试说')
    expect(fb.repeat_phrase).toBeDefined()
  })

  it('error fallback encourages retry', () => {
    const fb = getFallback('error')
    expect(fb.text).toContain('再试一次')
  })

  it('all fallbacks have emotion=encourage', () => {
    for (const trigger of ['wake', 'silence', 'error'] as const) {
      expect(getFallback(trigger).emotion).toBe('encourage')
    }
  })

  it('all fallbacks have should_tts=true', () => {
    for (const trigger of ['wake', 'silence', 'error'] as const) {
      expect(getFallback(trigger).should_tts).toBe(true)
    }
  })
})
