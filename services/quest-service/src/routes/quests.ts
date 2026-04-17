import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { QuestEngine } from '../services/quest-engine.js'

const completeQuestSchema = z.object({
  quest_id: z.string(),
  accuracy: z.number().min(0).max(100),
  fluency: z.number().min(0).max(100),
  vocabulary: z.number().min(0).max(100)
})

export async function registerQuestRoutes(app: FastifyInstance) {
  const questEngine = new QuestEngine()

  app.get('/api/v1/quests', async (request, reply) => {
    const { userId, sceneId } = request.query as { userId?: string; sceneId?: string }
    const quests = await questEngine.getUserQuests(userId || 'anonymous', sceneId)
    return reply.send(quests)
  })

  app.post('/api/v1/quests/complete', async (request, reply) => {
    const body = completeQuestSchema.parse(request.body)
    const result = await questEngine.completeQuest(
      'anonymous',
      body.quest_id,
      { accuracy: body.accuracy, fluency: body.fluency, vocabulary: body.vocabulary }
    )
    return reply.send(result)
  })

  app.post('/api/v1/quests/daily/generate', async (request, reply) => {
    const { userId } = request.query as { userId?: string }
    const quests = await questEngine.generateDailyQuests(userId || 'anonymous')
    return reply.send(quests)
  })
}
