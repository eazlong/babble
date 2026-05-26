import { describe, expect, it } from 'vitest'
import { CoachHintGenerator } from '../services/coach-hint-generator.js'

describe('CoachHintGenerator', () => {
  const generator = new CoachHintGenerator()

  describe('wake trigger', () => {
    it('returns encourage emotion, contains "Can you help me?", should_tts: true, ttl_ms: 8000', () => {
      const hint = generator.generate({ trigger: 'wake', errors: [] })

      expect(hint.emotion).toBe('encourage')
      expect(hint.text).toContain('Can you help me?')
      expect(hint.repeat_phrase).toBe('Can you help me?')
      expect(hint.should_tts).toBe(true)
      expect(hint.ttl_ms).toBe(8000)
    })

    it('contains Chinese helper text 我来帮你', () => {
      const hint = generator.generate({ trigger: 'wake', errors: [] })
      expect(hint.text).toContain('我来帮你')
    })
  })

  describe('silence trigger', () => {
    it('returns neutral emotion, contains "I need help"', () => {
      const hint = generator.generate({ trigger: 'silence', errors: [] })

      expect(hint.emotion).toBe('neutral')
      expect(hint.text).toContain('I need help')
      expect(hint.repeat_phrase).toBe('I need help.')
      expect(hint.should_tts).toBe(true)
      expect(hint.ttl_ms).toBe(8000)
    })

    it('contains encouraging Chinese text 想不出来也没关系', () => {
      const hint = generator.generate({ trigger: 'silence', errors: [] })
      expect(hint.text).toContain('想不出来也没关系')
    })
  })

  describe('error trigger', () => {
    it('returns first error correction, encourage emotion', () => {
      const hint = generator.generate({
        trigger: 'error',
        errors: [
          {
            type: 'grammar',
            severity: 'high',
            original_text: 'I am go',
            correction: 'I am going',
            explanation: 'Use present continuous for something happening now.',
          },
        ],
      })

      expect(hint.text).toContain('I am going')
      expect(hint.repeat_phrase).toBe('I am going')
      expect(hint.emotion).toBe('encourage')
      expect(hint.should_tts).toBe(true)
      expect(hint.ttl_ms).toBe(8000)
    })

    it('contains Chinese encouragement text 差一点点', () => {
      const hint = generator.generate({
        trigger: 'error',
        errors: [
          {
            type: 'grammar',
            severity: 'high',
            original_text: 'he dont like it',
            correction: "he doesn't like it",
            explanation: 'Use "doesn\'t" with he/she/it.',
          },
        ],
      })

      expect(hint.text).toContain('可以说')
      expect(hint.text).toContain('差一点点')
    })

    it('uses first error when multiple errors exist', () => {
      const hint = generator.generate({
        trigger: 'error',
        errors: [
          {
            type: 'grammar',
            severity: 'high',
            original_text: 'I am go',
            correction: 'I am going',
            explanation: 'Use present continuous.',
          },
          {
            type: 'grammar',
            severity: 'high',
            original_text: "he don't",
            correction: "he doesn't",
            explanation: 'Use "doesn\'t" with he/she/it.',
          },
        ],
      })

      expect(hint.repeat_phrase).toBe('I am going')
      expect(hint.text).toContain('I am going')
    })
  })

  describe('repeat_phrase', () => {
    it('wake repeat_phrase is "Can you help me?"', () => {
      const hint = generator.generate({ trigger: 'wake', errors: [] })
      expect(hint.repeat_phrase).toBe('Can you help me?')
    })

    it('silence repeat_phrase is "I need help."', () => {
      const hint = generator.generate({ trigger: 'silence', errors: [] })
      expect(hint.repeat_phrase).toBe('I need help.')
    })

    it('error repeat_phrase matches correction', () => {
      const hint = generator.generate({
        trigger: 'error',
        errors: [
          {
            type: 'vocabulary',
            severity: 'high',
            original_text: 'bigly',
            correction: 'very much',
            explanation: 'Use standard vocabulary.',
          },
        ],
      })

      expect(hint.repeat_phrase).toBe('very much')
    })
  })
})
