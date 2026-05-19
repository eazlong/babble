import { describe, expect, it } from 'vitest'
import { CoachHintGenerator } from '../services/coach-hint-generator.js'

describe('CoachHintGenerator', () => {
  const generator = new CoachHintGenerator()

  it('creates a Chinese-first correction hint with repeat phrase', () => {
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

    expect(hint.text).toContain('可以说')
    expect(hint.repeat_phrase).toBe('I am going')
    expect(hint.should_tts).toBe(true)
  })

  it('creates a silence hint for 15-second pauses', () => {
    const hint = generator.generate({ trigger: 'silence', errors: [] })
    expect(hint.text).toContain('想不出来也没关系')
    expect(hint.repeat_phrase).toBe('I need help.')
  })

  it('creates a wake hint that responds immediately', () => {
    const hint = generator.generate({ trigger: 'wake', errors: [] })
    expect(hint.text).toContain('我来帮你')
    expect(hint.repeat_phrase).toBe('Can you help me?')
  })
})
