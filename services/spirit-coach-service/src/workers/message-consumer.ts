import Redis from 'ioredis'
import { ErrorDetector, DetectedError } from '../services/error-detector.js'

export class MessageConsumer {
  private redis: Redis
  private errorDetector: ErrorDetector

  constructor(redisUrl: string) {
    this.redis = new Redis(redisUrl)
    this.errorDetector = new ErrorDetector()
  }

  async start(): Promise<void> {
    console.log('Spirit coach message consumer started')

    while (true) {
      try {
        const result = await this.redis.xread(
          'BLOCK', 5000,
          'STREAMS',
          'spirit_coach_queue',
          '0'
        )

        if (!result) continue

        for (const [stream, messages] of result) {
          for (const [messageId, raw] of messages) {
            const data: Record<string, string> = {}
            for (let i = 0; i < raw.length; i += 2) {
              data[raw[i]] = raw[i + 1] || ''
            }
            await this.processMessage(data)
            await this.redis.xdel('spirit_coach_queue', messageId)
          }
        }
      } catch (error) {
        console.error('Message consumer error:', error)
        await new Promise(resolve => setTimeout(resolve, 1000))
      }
    }
  }

  private async processMessage(data: Record<string, string>): Promise<void> {
    const { turn_id, session_id, asr_text, user_id } = data

    const errors = await this.errorDetector.analyze(asr_text)
    const highErrors = errors.filter(e => e.severity === 'high')

    for (const error of highErrors) {
      console.log(`[${session_id}] Error detected: ${error.type} - ${error.correction}`)
      // In production: save to DB and push notification
    }
  }

  stop(): void {
    this.redis.quit()
  }
}
