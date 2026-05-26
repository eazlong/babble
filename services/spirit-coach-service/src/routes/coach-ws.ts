import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { CoachSessionManager } from '../services/coach-session-manager.js'

const querySchema = z.object({
  session_id: z.string().min(1),
})

export async function registerCoachWsRoute(app: FastifyInstance, sessionManager: CoachSessionManager) {
  app.get('/ws/coach', { websocket: true }, (connection, request) => {
    const query = querySchema.parse(request.query)
    sessionManager.attach(query.session_id, connection)

    connection.on('close', () => {
      sessionManager.detach(query.session_id)
    })
  })
}
