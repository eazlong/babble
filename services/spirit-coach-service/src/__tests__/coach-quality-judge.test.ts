import { describe, expect, it } from 'vitest'
import { CoachQualityJudge, QUALITY_JUDGE_PROMPT } from '../services/coach-quality-judge.js'

describe('CoachQualityJudge', () => {
  it('passes a friendly A1 correction with Xiao Fei Mao persona', () => {
    const judge = new CoachQualityJudge()
    const result = judge.evaluate({
      playerLevel: 'A1',
      trigger: 'error',
      playerText: 'I am go to school',
      coachText: '喵~ 差一点点！正确的说法是：I am going。跟着小飞猫再试一次吧！',
      repeatPhrase: 'I am going',
    })

    expect(result.pass).toBe(true)
    expect(result.averageScore).toBeGreaterThanOrEqual(3.5)
    expect(result.scores.personaConsistency).toBe(5)
    expect(result.scores.friendliness).toBe(5)
    expect(result.scores.correctionAccuracy).toBe(5)
  })

  it('fails unfriendly coach output', () => {
    const judge = new CoachQualityJudge()
    const result = judge.evaluate({
      playerLevel: 'A1',
      trigger: 'error',
      playerText: 'I am go',
      coachText: 'This is bad and wrong again.',
      repeatPhrase: '',
    })

    expect(result.pass).toBe(false)
    expect(result.scores.friendliness).toBe(1)
    expect(result.reasons.length).toBeGreaterThan(0)
  })

  it('checks A1 language ratio expects Chinese', () => {
    const judge = new CoachQualityJudge({ threshold: 4.5 })
    const result = judge.evaluate({
      playerLevel: 'A1',
      trigger: 'wake',
      coachText: 'Try saying: Can you help me?',
      repeatPhrase: 'Can you help me?',
    })

    expect(result.scores.languageRatio).toBeLessThan(3)
    expect(result.pass).toBe(false)
  })

  it('checks B2 language ratio allows mostly English', () => {
    const judge = new CoachQualityJudge()
    const result = judge.evaluate({
      playerLevel: 'B2',
      trigger: 'error',
      coachText: 'Meow~ Close! The correct form is "He does not" with third-person singular.',
      repeatPhrase: 'He does not',
    })

    expect(result.scores.languageRatio).toBe(5)
  })

  it('includes the LLM-as-judge prompt dimensions', () => {
    expect(QUALITY_JUDGE_PROMPT).toContain('personaConsistency')
    expect(QUALITY_JUDGE_PROMPT).toContain('friendliness')
    expect(QUALITY_JUDGE_PROMPT).toContain('correctionAccuracy')
    expect(QUALITY_JUDGE_PROMPT).toContain('languageRatio')
  })
})
