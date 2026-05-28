import Fastify from 'fastify'
import cors from '@fastify/cors'
import websocket from '@fastify/websocket'
import { createClient, SupabaseClient } from '@supabase/supabase-js'
import { registerQuestRoutes } from './routes/quests.js'
import { registerQuestWsRoute } from './routes/quest-ws.js'
import { QuestSessionManager } from './services/quest-session-manager.js'

declare module 'fastify' {
  interface FastifyInstance {
    supabase: SupabaseClient
    questSessionManager: QuestSessionManager
  }
}

const app = Fastify({ logger: true })

app.register(cors, { origin: true })
app.register(websocket)

// Initialize Supabase client (same as auth-service)
const supabaseUrl = process.env.SUPABASE_URL || 'https://localhost:54321'
const supabaseKey = process.env.SUPABASE_KEY || 'dev-key'
app.decorate('supabase', createClient(supabaseUrl, supabaseKey))

// Initialize quest WebSocket session manager
const questSessionManager = new QuestSessionManager()
app.decorate('questSessionManager', questSessionManager)

app.register(registerQuestRoutes, { questSessionManager })
app.register(registerQuestWsRoute, questSessionManager)

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
