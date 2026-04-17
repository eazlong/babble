import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { DropEngine } from '../services/drop-engine.js'

const dropSchema = z.object({
  quest_type: z.enum(['main', 'side', 'daily']),
  cefr_level: z.string().default('A1')
})

export async function registerRewardRoutes(app: FastifyInstance) {
  const dropEngine = new DropEngine()

  app.post('/api/v1/rewards/roll', async (request, reply) => {
    const body = dropSchema.parse(request.body)
    const drop = await dropEngine.calculateDrop(
      'anonymous',
      body.quest_type,
      body.cefr_level
    )
    return reply.send(drop)
  })

  app.get('/api/v1/rewards/inventory', async (request, reply) => {
    // MVP: Return sample inventory
    return reply.send([
      { item_id: 'item_1', name: '铜币', rarity: 'common', equipped: false },
      { item_id: 'item_2', name: '银币', rarity: 'rare', equipped: true }
    ])
  })
}
