import Fastify from 'fastify'
import cors from '@fastify/cors'
import websocket from '@fastify/websocket'
import Redis from 'ioredis'
import { registerCoachRoutes } from './routes/coach.js'
import { registerCoachWsRoute } from './routes/coach-ws.js'
import { CoachSessionManager } from './services/coach-session-manager.js'
import { TriggerClassifier } from './services/trigger-classifier.js'
import { InterventionPolicy } from './services/intervention-policy.js'
import { CoachHintGenerator } from './services/coach-hint-generator.js'
import { CoachInputConsumer } from './workers/coach-input-consumer.js'
import { ErrorDetector } from './services/error-detector.js'

const app = Fastify({ logger: true })

const redisUrl = process.env.REDIS_URL ?? 'redis://localhost:6380'
const redis = new Redis(redisUrl)

const sessionManager = new CoachSessionManager()
const errorDetector = new ErrorDetector()
const classifier = new TriggerClassifier(errorDetector)
const policy = new InterventionPolicy(redis)
const generator = new CoachHintGenerator()

const consumer = new CoachInputConsumer(
  redis,
  classifier,
  policy,
  generator,
  sessionManager,
)

app.register(cors, { origin: true })
app.register(websocket)
app.register(async (instance) => {
  await registerCoachRoutes(instance, redis)
})
app.register(async (instance) => {
  await registerCoachWsRoute(instance, sessionManager)
})

app.get('/health', async () => ({
  status: 'ok',
  service: 'spirit-coach-service',
  timestamp: new Date().toISOString(),
}))

const start = async () => {
  try {
    await app.listen({ port: 8305, host: '0.0.0.0' })
    app.log.info('Spirit coach service running on port 8305')
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}

if (process.env.NODE_ENV !== 'test') {
  start()
  setInterval(() => {
    void consumer.consumeOnce().catch((error) => app.log.error(error))
  }, 200)
}

export default app
