import { z } from 'zod'

export const judgeScoreSchema = z.object({
  personaConsistency: z.number().min(1).max(5),
  friendliness: z.number().min(1).max(5),
  correctionAccuracy: z.number().min(1).max(5),
  languageRatio: z.number().min(1).max(5),
})

export const coachQualityJudgementSchema = z.object({
  scores: judgeScoreSchema,
  averageScore: z.number().min(1).max(5),
  pass: z.boolean(),
  reasons: z.array(z.string()).default([]),
})

export type CoachQualityJudgement = z.infer<typeof coachQualityJudgementSchema>

export interface JudgeInput {
  playerLevel: 'A1' | 'A2' | 'B1' | 'B2'
  trigger: 'wake' | 'error' | 'silence'
  playerText?: string
  npcResponse?: string
  coachText: string
  repeatPhrase?: string
}

export interface CoachQualityJudgeOptions {
  threshold?: number
}

/**
 * Local deterministic quality judge used in CI.
 *
 * It intentionally avoids an external LLM call so CI remains stable and cheap,
 * while enforcing the same dimensions the future LLM-as-judge prompt will use:
 * persona consistency, friendliness, correction accuracy, and language ratio.
 */
export class CoachQualityJudge {
  private readonly threshold: number

  constructor(options: CoachQualityJudgeOptions = {}) {
    this.threshold = options.threshold ?? 3.5
  }

  evaluate(input: JudgeInput): CoachQualityJudgement {
    const scores = {
      personaConsistency: scorePersona(input.coachText),
      friendliness: scoreFriendliness(input.coachText),
      correctionAccuracy: scoreCorrection(input),
      languageRatio: scoreLanguageRatio(input.playerLevel, input.coachText),
    }

    const averageScore = roundToOneDecimal(
      (scores.personaConsistency + scores.friendliness + scores.correctionAccuracy + scores.languageRatio) / 4
    )

    const reasons = buildReasons(scores)
    const result = {
      scores,
      averageScore,
      pass: averageScore >= this.threshold,
      reasons,
    }

    return coachQualityJudgementSchema.parse(result)
  }
}

export const QUALITY_JUDGE_PROMPT = `
You are an evaluator for Xiao Fei Mao, a friendly bilingual English coach for Chinese elementary students.
Score the coach response from 1 to 5 on:
1. personaConsistency — keeps Xiao Fei Mao's warm, cat-like, encouraging persona.
2. friendliness — never criticizes, shames, or discourages the child.
3. correctionAccuracy — for error triggers, gives a plausible correction; for wake/silence, gives useful help.
4. languageRatio — follows the player's CEFR level language mix (A1 mostly Chinese, B2 mostly English).
Return JSON: { scores, averageScore, pass, reasons }.
`

function scorePersona(text: string): number {
  return text.includes('喵') || text.toLowerCase().includes('xiao fei mao') ? 5 : 3
}

function scoreFriendliness(text: string): number {
  const lower = text.toLowerCase()
  const negativeWords = ['bad', 'wrong again', 'stupid', '笨', '差劲', '不行']
  return negativeWords.some((word) => lower.includes(word)) ? 1 : 5
}

function scoreCorrection(input: JudgeInput): number {
  if (input.trigger === 'error') {
    const hasRepeatPhrase = Boolean(input.repeatPhrase && input.repeatPhrase.length > 0)
    const mentionsCorrection = /correct|say|说|正确|试试/i.test(input.coachText)
    return hasRepeatPhrase && mentionsCorrection ? 5 : 2
  }

  const usefulHelp = /try|say|help|试试|可以|帮/i.test(input.coachText)
  return usefulHelp ? 5 : 3
}

function scoreLanguageRatio(level: JudgeInput['playerLevel'], text: string): number {
  const hasChinese = /[一-鿿]/.test(text)
  const latinChars = text.match(/[A-Za-z]/g)?.length ?? 0

  if (level === 'A1') {
    return hasChinese ? 5 : 2
  }

  if (level === 'B2') {
    return latinChars > 20 ? 5 : 3
  }

  return hasChinese || latinChars > 10 ? 5 : 3
}

function buildReasons(scores: z.infer<typeof judgeScoreSchema>): string[] {
  const reasons: string[] = []
  for (const [key, value] of Object.entries(scores)) {
    if (value < 3) reasons.push(`${key} scored ${value}`)
  }
  return reasons
}

function roundToOneDecimal(value: number): number {
  return Math.round(value * 10) / 10
}
