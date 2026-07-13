import { randomUUID } from 'node:crypto'
import { coachInputSchema, type CoachInput } from '../types/coach-events.js'
import { getFallback } from '../services/fallback-templates.js'
import type { Trigger, StreakData } from '../services/prompt-builder.js'
import type { StreakTracker } from '../services/streak-tracker.js'

export interface LLMCoachLike {
  generate(input: CoachInput, trigger: Trigger, streak?: StreakData): Promise<{
    text: string
    emotion: string
    repeat_phrase?: string
    should_tts: boolean
    ttl_ms: number
  }>
}

export class CoachInputConsumer {
  constructor(
    private readonly redis: {
      xread(...args: unknown[]): Promise<unknown>
      xadd(stream: string, id: string, ...pairs: string[]): Promise<string>
      xdel(stream: string, id: string): Promise<number>
    },
    private readonly classifier: { classify(input: ReturnType<typeof coachInputSchema.parse>): Promise<any> },
    private readonly policy: { shouldIntervene(arg: { trigger: 'wake' | 'error' | 'silence'; userId: string }): Promise<boolean>; markIntervened(arg: { trigger: 'wake' | 'error' | 'silence'; userId: string }): Promise<void> },
    private readonly llmCoach: LLMCoachLike,
    private readonly sessionManager: { push(sessionId: string, payload: Record<string, unknown>): Promise<void> },
    private readonly streakTracker: StreakTracker,
    private readonly logger: { warn(...args: unknown[]): void; error(...args: unknown[]): void } = console,
  ) {}

  async consumeOnce() {
    const result = await this.redis.xread('COUNT', 10, 'BLOCK', 1000, 'STREAMS', 'coach.input', '0') as [string, [string, string[]][]][] | null
    if (!result) {
      return
    }

    for (const [, messages] of result) {
      for (const [messageId, raw] of messages) {
        const data: Record<string, unknown> = {}
        for (let i = 0; i < raw.length; i += 2) {
          const key = raw[i]
          const value = raw[i + 1]
          if (key === 'timestamp' || key === 'silence_ms') {
            data[key] = Number(value)
          } else if (key === 'player_level') {
            data[key] = value
          } else if (key === 'recent_turns') {
            try {
              data[key] = JSON.parse(value as string)
            } catch {
              data[key] = []
            }
          } else {
            data[key] = value
          }
        }

        const input = coachInputSchema.parse(data)
        const classified = await this.classifier.classify(input)
        if (classified === null) {
          await this.redis.xdel('coach.input', messageId)
          continue
        }

        const trigger = classified.trigger as Trigger

        const allowed = await this.policy.shouldIntervene({
          trigger,
          userId: input.user_id,
        })

        if (!allowed) {
          await this.redis.xdel('coach.input', messageId)
          continue
        }

        let response: {
          text: string
          emotion: string
          repeat_phrase?: string
          should_tts: boolean
          ttl_ms: number
        }

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
          response = await this.llmCoach.generate(input, trigger, streakData)
        } catch (err) {
          this.logger.warn('LLM coach failed, using fallback', {
            trigger,
            error: err instanceof Error ? err.message : String(err),
          })
          response = getFallback(trigger)
        }

        const payload = {
          event_id: randomUUID(),
          session_id: input.session_id,
          user_id: input.user_id,
          trigger,
          priority: classified.priority,
          text: response.text,
          repeat_phrase: response.repeat_phrase,
          emotion: response.emotion,
          should_tts: response.should_tts,
          ttl_ms: response.ttl_ms,
          timestamp: Date.now(),
        }

        const pairs = Object.entries(payload)
          .filter(([, value]) => value !== undefined)
          .flatMap(([key, value]) => [key, String(value)])

        await this.redis.xadd('coach.intervention', 'MAXLEN', '~', '10000', '*', ...pairs)
        await this.policy.markIntervened({ trigger, userId: input.user_id })
        await this.sessionManager.push(input.session_id, payload)
        await this.redis.xdel('coach.input', messageId)
      }
    }
  }
}
