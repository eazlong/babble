import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { QuestEngine } from '../services/quest-engine.js'
import { QuestSessionManager, createQuestEvent } from '../services/quest-session-manager.js'

const completeQuestSchema = z.object({
  quest_id: z.string(),
  accuracy: z.number().min(0).max(100),
  fluency: z.number().min(0).max(100),
  vocabulary: z.number().min(0).max(100)
})

const reportQuestSchema = z.object({
  user_id: z.string().optional(),
  quest_id: z.string(),
  scene_id: z.string(),
  scores: z.object({
    accuracy: z.number().min(0).max(100),
    fluency: z.number().min(0).max(100),
    vocabulary: z.number().min(0).max(100)
  }),
  player_input: z.string().optional()
})

export async function registerQuestRoutes(
  app: FastifyInstance,
  opts?: { questSessionManager?: QuestSessionManager }
) {
  const questEngine = new QuestEngine()
  const wsManager = opts?.questSessionManager

  /** Helper: emit WS event to user if WebSocket is available */
  function emitQuestEvent(userId: string, result: {
    badge_unlocked: string | null
    success: boolean
    lxp_earned: number
    stars_earned: number
    rewards: Array<{ item_id: string; name: string }>
    all_scene_quests_complete: boolean
    quest_id?: string
    scene_id?: string
  }) {
    if (!wsManager) return
    if (!result.success) return

    // Emit quest_completed
    wsManager.sendToUser(userId, createQuestEvent('quest_completed', {
      quest_id: result.quest_id || '',
      lxp_earned: result.lxp_earned,
      stars_earned: result.stars_earned,
      rewards: result.rewards,
      all_scene_quests_complete: result.all_scene_quests_complete,
    }))

    // Emit badge_unlocked if applicable
    if (result.badge_unlocked) {
      wsManager.sendToUser(userId, createQuestEvent('badge_unlocked', {
        badge_id: result.badge_unlocked,
      }))
    }
  }

  app.get('/api/v1/quests', async (request, reply) => {
    const { userId, sceneId } = request.query as { userId?: string; sceneId?: string }
    const quests = await questEngine.getUserQuests(userId || 'anonymous', sceneId)
    return reply.send(quests)
  })

  app.post('/api/v1/quests/complete', async (request, reply) => {
    const body = completeQuestSchema.parse(request.body)
    const userId = 'anonymous'
    const result = await questEngine.completeQuest(
      userId,
      body.quest_id,
      { accuracy: body.accuracy, fluency: body.fluency, vocabulary: body.vocabulary }
    )
    emitQuestEvent(userId, { ...result, quest_id: body.quest_id })
    return reply.send(result)
  })

  app.post('/api/v1/quests/daily/generate', async (request, reply) => {
    const { userId } = request.query as { userId?: string }
    const quests = await questEngine.generateDailyQuests(userId || 'anonymous')
    return reply.send(quests)
  })

  app.post('/api/v1/quests/report', async (request, reply) => {
    const body = reportQuestSchema.parse(request.body)
    const userId = body.user_id || 'anonymous'
    const result = await questEngine.reportQuestCompletion(
      userId,
      body.quest_id,
      body.scene_id,
      body.scores,
      body.player_input
    )
    emitQuestEvent(userId, { ...result, quest_id: body.quest_id, scene_id: body.scene_id })
    return reply.send(result)
  })

  app.get('/api/v1/quests/status', async (request, reply) => {
    const { user_id, scene_id } = request.query as { user_id?: string; scene_id?: string }
    if (!scene_id) {
      return reply.code(400).send({ error: 'scene_id query parameter is required' })
    }
    const status = await questEngine.getQuestStatus(user_id || 'anonymous', scene_id)
    return reply.send(status)
  })

  app.get('/api/v1/quests/daily', async (request, reply) => {
    const { user_id } = request.query as { user_id?: string }
    const quests = await questEngine.getDailyQuests(user_id || 'anonymous')
    return reply.send(quests)
  })

  app.post('/api/v1/quests/daily/:questId/complete', async (request, reply) => {
    const { questId } = request.params as { questId: string }
    const body = completeQuestSchema.parse(request.body)
    const { user_id } = request.query as { user_id?: string }
    const userId = user_id || 'anonymous'
    const result = await questEngine.completeDailyQuest(
      userId,
      questId,
      { accuracy: body.accuracy, fluency: body.fluency, vocabulary: body.vocabulary }
    )
    if (result.success && wsManager) {
      wsManager.sendToUser(userId, createQuestEvent('quest_completed', {
        quest_id: questId,
        quest_type: 'daily',
        message: result.message,
      }))
    }
    return reply.send(result)
  })
}
