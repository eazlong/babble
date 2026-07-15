import { randomUUID } from 'node:crypto'
import { getFallback } from './fallback-templates.js'
import type { LLMCallRecord, LLMTokenUsage } from './coach-metrics.js'
import type { StreakTracker } from './streak-tracker.js'
import type { Trigger, StreakData } from './prompt-builder.js'
import type { CoachInput, CoachIntervention, CoachResponse } from '../types/coach-events.js'

export interface LLMCoachLike {
  generate(input: CoachInput, trigger: Trigger, streak?: StreakData): Promise<CoachResponse>
  generateWithUsage?(input: CoachInput, trigger: Trigger, streak?: StreakData): Promise<{
    response: CoachResponse
    tokenUsage?: LLMTokenUsage
  }>
}

interface ClassifiedCoachInput {
  trigger: Trigger
  priority: number
}

export type CoachInterventionDecision =
  | { kind: 'skipped'; reason: 'no_trigger' | 'cooldown_blocked'; trigger?: Trigger }
  | {
      kind: 'intervention'
      intervention: CoachIntervention
      commit(): Promise<void>
      metadata: {
        trigger: Trigger
        fallback: boolean
        tokenUsage?: LLMTokenUsage
        latencyMs: number
      }
    }

export interface CoachInterventionEngineOptions {
  classifier: { classify(input: CoachInput): Promise<ClassifiedCoachInput | null> }
  policy: {
    shouldIntervene(arg: { trigger: Trigger; userId: string }): Promise<boolean>
    markIntervened(arg: { trigger: Trigger; userId: string }): Promise<void>
  }
  llmCoach: LLMCoachLike
  streakTracker: StreakTracker
  metrics?: { recordCall(record: LLMCallRecord): void }
  logger?: { warn(...args: unknown[]): void; error(...args: unknown[]): void }
  idGenerator?: () => string
  now?: () => number
}

export class CoachInterventionEngine {
  private readonly classifier: CoachInterventionEngineOptions['classifier']
  private readonly policy: CoachInterventionEngineOptions['policy']
  private readonly llmCoach: LLMCoachLike
  private readonly streakTracker: StreakTracker
  private readonly metrics?: CoachInterventionEngineOptions['metrics']
  private readonly logger: { warn(...args: unknown[]): void; error(...args: unknown[]): void }
  private readonly idGenerator: () => string
  private readonly now: () => number

  constructor(options: CoachInterventionEngineOptions) {
    this.classifier = options.classifier
    this.policy = options.policy
    this.llmCoach = options.llmCoach
    this.streakTracker = options.streakTracker
    this.metrics = options.metrics
    this.logger = options.logger ?? console
    this.idGenerator = options.idGenerator ?? randomUUID
    this.now = options.now ?? Date.now
  }

  async handle(input: CoachInput): Promise<CoachInterventionDecision> {
    const classified = await this.classifier.classify(input)
    if (classified === null) {
      return { kind: 'skipped', reason: 'no_trigger' }
    }

    const trigger = classified.trigger
    const allowed = await this.policy.shouldIntervene({
      trigger,
      userId: input.user_id,
    })

    if (!allowed) {
      return { kind: 'skipped', reason: 'cooldown_blocked', trigger }
    }

    let response: CoachResponse
    let tokenUsage: LLMTokenUsage | undefined
    let fallback = false
    const startTimeMs = this.now()

    // Update streak tracking based on trigger type.
    // Only error triggers reliably indicate a wrong answer; silence/wake
    // are ambiguous so we don't update the correct streak for them.
    if (trigger === 'error') {
      this.streakTracker.recordError(input.user_id)
    }

    const streakData: StreakData = {
      error_streak: this.streakTracker.getErrorStreak(input.user_id),
      correct_streak: this.streakTracker.getCorrectStreak(input.user_id),
    }

    try {
      if (this.llmCoach.generateWithUsage) {
        const resultWithUsage = await this.llmCoach.generateWithUsage(input, trigger, streakData)
        response = resultWithUsage.response
        tokenUsage = resultWithUsage.tokenUsage
      } else {
        response = await this.llmCoach.generate(input, trigger, streakData)
      }
    } catch (err) {
      this.logger.warn('LLM coach failed, using fallback', {
        trigger,
        error: err instanceof Error ? err.message : String(err),
      })
      fallback = true
      response = getFallback(trigger)
    }

    const latencyMs = this.now() - startTimeMs
    this.metrics?.recordCall({
      trigger,
      latencyMs,
      fallback,
      tokenUsage,
    })

    const intervention: CoachIntervention = {
      event_id: this.idGenerator(),
      session_id: input.session_id,
      user_id: input.user_id,
      trigger,
      priority: classified.priority,
      text: response.text,
      repeat_phrase: response.repeat_phrase,
      emotion: response.emotion,
      should_tts: response.should_tts,
      ttl_ms: response.ttl_ms,
      timestamp: this.now(),
    }

    return {
      kind: 'intervention',
      intervention,
      commit: () => this.policy.markIntervened({ trigger, userId: input.user_id }),
      metadata: {
        trigger,
        fallback,
        tokenUsage,
        latencyMs,
      },
    }
  }
}
