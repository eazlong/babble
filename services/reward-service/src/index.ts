import Fastify from 'fastify'
import cors from '@fastify/cors'
import { registerRewardRoutes } from './routes/rewards.js'

const app = Fastify({ logger: true })

app.register(cors, { origin: true })
app.register(registerRewardRoutes)

app.get('/health', async () => ({
  status: 'ok',
  service: 'reward-service',
  timestamp: new Date().toISOString()
}))

const start = async () => {
  try {
    await app.listen({ port: 8007, host: '0.0.0.0' })
    app.log.info('Reward service running on port 8007')
  } catch (err) {
    app.error(err)
    process.exit(1)
  }
}

if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
