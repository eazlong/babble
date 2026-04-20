import Fastify from 'fastify'
import cors from '@fastify/cors'
import { registerSceneRoutes } from './routes/scenes.js'

const app = Fastify({ logger: true })

app.register(cors, { origin: true })

app.register(registerSceneRoutes)

app.get('/health', async () => ({
  status: 'ok',
  service: 'content-service',
  timestamp: new Date().toISOString()
}))

const start = async () => {
  try {
    await app.listen({ port: 8308, host: '0.0.0.0' })
    app.log.info('Content service running on port 8308')
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}

if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
