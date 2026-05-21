import Fastify from 'fastify'
import cors from '@fastify/cors'
import Redis from 'ioredis'
import { registerDialogueRoutes } from './routes/dialogue.js'
import { CoachPublisher } from './services/coach-publisher.js'

const app = Fastify({ logger: true })

const redisUrl = process.env.REDIS_URL ?? 'redis://localhost:6380'
const coachPublisher = new CoachPublisher(new Redis(redisUrl) as any)

app.register(cors, { origin: true })

app.register(async (instance) => {
  await registerDialogueRoutes(instance, coachPublisher)
})

app.get('/health', async () => ({
  status: 'ok',
  service: 'dialogue-service',
  timestamp: new Date().toISOString(),
}))

const start = async () => {
  try {
    await app.listen({ port: 8302, host: '0.0.0.0' })
    app.log.info('Dialogue service running on port 8302')
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}

if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
