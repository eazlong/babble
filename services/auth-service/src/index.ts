import Fastify from 'fastify'
import cors from '@fastify/cors'
import { createClient, SupabaseClient } from '@supabase/supabase-js'
import { registerRoutes } from './routes/register.js'
import { registerLoginRoutes } from './routes/login.js'

declare module 'fastify' {
  interface FastifyInstance {
    supabase: SupabaseClient
  }
}

const app = Fastify({ logger: true })

app.register(cors, { origin: true })

// Initialize Supabase client
const supabaseUrl = process.env.SUPABASE_URL || 'https://localhost:54321'
const supabaseKey = process.env.SUPABASE_KEY || 'dev-key'
app.decorate('supabase', createClient(supabaseUrl, supabaseKey))

// Register routes
app.register(registerRoutes)
app.register(registerLoginRoutes)

app.get('/health', async () => ({
  status: 'ok',
  service: 'auth-service',
  timestamp: new Date().toISOString()
}))

const start = async () => {
  try {
    await app.listen({ port: 8003, host: '0.0.0.0' })
    app.log.info('Auth service running on port 8003')
  } catch (err) {
    app.log.error(err)
    process.exit(1)
  }
}

if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
