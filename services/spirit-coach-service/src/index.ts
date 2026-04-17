import Fastify from 'fastify'
import cors from '@fastify/cors'
import { registerCoachRoutes } from './routes/coach.js'

const app = Fastify({ logger: true })

app.register(cors, { origin: true })
app.register(registerCoachRoutes)

app.get('/health', async () => ({
  status: 'ok',
  service: 'spirit-coach-service',
  timestamp: new Date().toISOString()
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
}

export default app
