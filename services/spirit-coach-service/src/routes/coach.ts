import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import Redis from 'ioredis'
import { ErrorDetector } from '../services/error-detector.js'
import { coachInputSchema } from '../types/coach-events.js'

const analyzeSchema = z.object({
  text: z.string().min(1).max(500),
  expected_level: z.string().default('A1'),
})

export async function registerCoachRoutes(app: FastifyInstance, redis: Redis) {
  const errorDetector = new ErrorDetector()

  app.post('/api/v1/coach/analyze', async (request, reply) => {
    const body = analyzeSchema.parse(request.body)
    const errors = await errorDetector.analyze(body.text, body.expected_level)

    return reply.send({
      errors: errors.filter(e => e.severity === 'high'),
      total_errors: errors.length,
    })
  })

  app.post('/api/v1/coach/events', async (request, reply) => {
    const body = coachInputSchema.parse(request.body)

    const pairs: string[] = []
    for (const [key, value] of Object.entries(body)) {
      pairs.push(key, String(value))
    }

    await redis.xadd('coach.input', '*', ...pairs)

    return reply.status(202).send({ status: 'accepted' })
  })
}
