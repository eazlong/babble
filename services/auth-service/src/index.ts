import Fastify from 'fastify'
import cors from '@fastify/cors'
import type pg from 'pg'
import { registerRoutes } from './routes/register.js'
import { registerLoginRoutes } from './routes/login.js'
import { registerParentDashboardRoutes } from './routes/parent-dashboard.js'
import { applySchema, makePool, type Db } from './db.js'

declare module 'fastify' {
  interface FastifyInstance {
    pool: pg.Pool
    db: Db
  }
}

const app = Fastify({ logger: true })

app.register(cors, { origin: true })

// Plain-Postgres connection pool (replaces the former Supabase client).
app.decorate('pool', makePool())
app.decorate('db', {
  pool: app.pool,
  query: async (text: string, params?: unknown[]) => {
    const res = await app.pool.query(text, params as any[])
    return res.rows
  }
})

// Register routes
app.register(registerRoutes)
app.register(registerLoginRoutes)
app.register(registerParentDashboardRoutes)

app.get('/health', async () => ({
  status: 'ok',
  service: 'auth-service',
  timestamp: new Date().toISOString()
}))

const start = async () => {
  // Bootstrap idempotent schema (safe on empty local Postgres).
  await applySchema(app)
  app.log.info('Schema bootstrap complete')
  await app.listen({ port: 8303, host: '0.0.0.0' })
  app.log.info('Auth service running on port 8303')
}

if (process.env.NODE_ENV !== 'test') {
  start()
}

export default app
