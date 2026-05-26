import { randomUUID } from 'node:crypto'
import { coachInputSchema } from '../types/coach-events.js'

export class CoachInputConsumer {
  constructor(
    private readonly redis: {
      xread(...args: unknown[]): Promise<unknown>
      xadd(stream: string, id: string, ...pairs: string[]): Promise<string>
      xdel(stream: string, id: string): Promise<number>
    },
    private readonly classifier: { classify(input: ReturnType<typeof coachInputSchema.parse>): Promise<any> },
    private readonly policy: { shouldIntervene(arg: { trigger: 'wake' | 'error' | 'silence'; userId: string }): Promise<boolean>; markIntervened(arg: { trigger: 'wake' | 'error' | 'silence'; userId: string }): Promise<void> },
    private readonly generator: { generate(arg: { trigger: 'wake' | 'error' | 'silence'; errors: any[] }): { text: string; repeat_phrase?: string; emotion: string; should_tts: boolean; ttl_ms: number } },
    private readonly sessionManager: { push(sessionId: string, payload: Record<string, unknown>): Promise<void> },
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
          data[key] = key === 'timestamp' || key === 'silence_ms' ? Number(value) : value
        }

        const input = coachInputSchema.parse(data)
        const classified = await this.classifier.classify(input)
        if (classified === null) {
          await this.redis.xdel('coach.input', messageId)
          continue
        }

        const allowed = await this.policy.shouldIntervene({
          trigger: classified.trigger,
          userId: input.user_id,
        })

        if (!allowed) {
          await this.redis.xdel('coach.input', messageId)
          continue
        }

        const hint = this.generator.generate({
          trigger: classified.trigger,
          errors: classified.errors,
        })

        const payload = {
          event_id: randomUUID(),
          session_id: input.session_id,
          user_id: input.user_id,
          trigger: classified.trigger,
          priority: classified.priority,
          text: hint.text,
          repeat_phrase: hint.repeat_phrase,
          emotion: hint.emotion,
          should_tts: hint.should_tts,
          ttl_ms: hint.ttl_ms,
          timestamp: Date.now(),
        }

        const pairs = Object.entries(payload)
          .filter(([, value]) => value !== undefined)
          .flatMap(([key, value]) => [key, String(value)])

        await this.redis.xadd('coach.intervention', 'MAXLEN', '~', '10000', '*', ...pairs)
        await this.policy.markIntervened({ trigger: classified.trigger, userId: input.user_id })
        await this.sessionManager.push(input.session_id, payload)
        await this.redis.xdel('coach.input', messageId)
      }
    }
  }
}
