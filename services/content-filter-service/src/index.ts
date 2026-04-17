import Fastify from 'fastify'
import { ContentFilter } from './services/moderation.js'

const app = Fastify({ logger: true })
const contentFilter = new ContentFilter()

app.get('/health', async () => ({
  status: 'ok',
  service: 'content-filter-service',
  timestamp: new Date().toISOString()
}))

app.post('/api/v1/moderation/check', async (request, reply) => {
  const { text, isChildMode } = request.body as { text: string; isChildMode?: boolean }
  const result = await contentFilter.check(text, isChildMode)
  return reply.send(result)
})

const start = async () => {
  try {
    await app.listen({ port: 8004, host: '0.0.0.0' })
    app.log.info('Content filter service running on port 8004')
  } catch (err) {
    app.error(err)
    process.exit(1)
  }
}

if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
