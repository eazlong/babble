import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { QuestSessionManager } from '../services/quest-session-manager.js'

const querySchema = z.object({
  user_id: z.string().min(1).default('anonymous'),
})

export async function registerQuestWsRoute(app: FastifyInstance, sessionManager: QuestSessionManager) {
  app.get('/ws/quest', { websocket: true }, (connection, request) => {
    const parsed = querySchema.safeParse(request.query)
    if (!parsed.success) {
      connection.socket.close(1008, 'Missing user_id query parameter')
      return
    }

    const userId = parsed.data.user_id
    sessionManager.attach(userId, connection.socket)

    connection.socket.on('close', () => {
      sessionManager.detach(userId)
    })

    connection.socket.on('error', (err) => {
      app.log.error(`[QuestWS] Error for user ${userId}:`, err.message)
      sessionManager.detach(userId)
    })
  })
}
