import Fastify from 'fastify'
import cors from '@fastify/cors'
import { registerDialogueRoutes } from './routes/dialogue.js'

const app = Fastify({ logger: true })

app.register(cors, { origin: true })

app.register(registerDialogueRoutes)

app.get('/health', async () => ({
  status: 'ok',
  service: 'dialogue-service',
  timestamp: new Date().toISOString()
}))

const start = async () => {
  try {
    await app.listen({ port: 8002, host: '0.0.0.0' })
    app.log.info('Dialogue service running on port 8002')
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}

if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
