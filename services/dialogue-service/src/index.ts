import Fastify from 'fastify'
import cors from '@fastify/cors'

const app = Fastify({ logger: true })

app.register(cors, { origin: true })

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
    app.error(err)
    process.exit(1)
  }
}

// Only start the server if not running in test mode
if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
