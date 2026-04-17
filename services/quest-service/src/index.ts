import Fastify from 'fastify'
import cors from '@fastify/cors'
import { registerQuestRoutes } from './routes/quests.js'

const app = Fastify({ logger: true })

app.register(cors, { origin: true })
app.register(registerQuestRoutes)

app.get('/health', async () => ({
  status: 'ok',
  service: 'quest-service',
  timestamp: new Date().toISOString()
}))

const start = async () => {
  try {
    await app.listen({ port: 8306, host: '0.0.0.0' })
    app.log.info('Quest service running on port 8306')
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}

if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
