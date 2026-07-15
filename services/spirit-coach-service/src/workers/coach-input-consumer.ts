import { coachInputSchema, type CoachInput } from '../types/coach-events.js'
import type { CoachInterventionDecision } from '../services/coach-intervention-engine.js'

export class CoachInputConsumer {
  constructor(
    private readonly redis: {
      xread(...args: unknown[]): Promise<unknown>
      xadd(stream: string, id: string, ...pairs: string[]): Promise<string>
      xdel(stream: string, id: string): Promise<number>
    },
    private readonly engine: { handle(input: CoachInput): Promise<CoachInterventionDecision> },
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
        const decision = await this.engine.handle(input)
        if (decision.kind === 'skipped') {
          await this.redis.xdel('coach.input', messageId)
          continue
        }

        const payload = decision.intervention
        const pairs = Object.entries(payload)
          .filter(([, value]) => value !== undefined)
          .flatMap(([key, value]) => [key, String(value)])

        await this.redis.xadd('coach.intervention', 'MAXLEN', '~', '10000', '*', ...pairs)
        await decision.commit()
        await this.sessionManager.push(input.session_id, payload)
        await this.redis.xdel('coach.input', messageId)
      }
    }
  }
}
