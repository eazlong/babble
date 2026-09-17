import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { QuestSessionManager } from '../services/quest-session-manager.js'

const querySchema = z.object({
  user_id: z.string().min(1).default('anonymous'),
})

export async function registerQuestWsRoute(app: FastifyInstance, sessionManager: QuestSessionManager) {
  // @fastify/websocket v10 起 handler 的第一个参数**就是** WebSocket 本身
  // （`WebsocketHandler = (socket, request) => void`）。v7/v8 那种
  // `(connection, request)` + `connection.socket` 的写法已被移除，多写这一层
  // 拿到的是 undefined —— 不只是类型报错，而是 /ws/quest 在运行时必然抛
  // "Cannot read properties of undefined (reading 'on')"。
  app.get('/ws/quest', { websocket: true }, (socket, request) => {
    const parsed = querySchema.safeParse(request.query)
    if (!parsed.success) {
      socket.close(1008, 'Missing user_id query parameter')
      return
    }

    const userId = parsed.data.user_id
    sessionManager.attach(userId, socket)

    socket.on('close', () => {
      sessionManager.detach(userId)
    })

    socket.on('error', (err) => {
      // pino 的 LogFn 只有在消息里带 printf 占位符时才接受附加参数，
      // 所以错误对象要以 bindings 形式放在第一个参数（同时也保留 stack）。
      app.log.error({ err }, `[QuestWS] Error for user ${userId}`)
      sessionManager.detach(userId)
    })
  })
}
