import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { NPCEngine } from '../services/npc-engine.js'

const dialogueSchema = z.object({
  npc_id: z.string(),
  player_input: z.string().min(1).max(500),
  session_id: z.string(),
  language: z.string().default('en')
})

export async function registerDialogueRoutes(app: FastifyInstance) {
  const npcEngine = new NPCEngine()

  app.post('/api/v1/dialogue', async (request, reply) => {
    const body = dialogueSchema.parse(request.body)

    // MVP: Use a default NPC profile
    const npcProfile = {
      name: 'Default NPC',
      npc_type: 'merchant',
      language_style: 'friendly',
      formality: 'informal' as const,
      vocabulary_level: 'basic' as const,
      personality: 'helpful'
    }

    const result = await npcEngine.processDialogue(
      {
        ...body,
        user_id: 'anonymous',
        cefr_level: 'A1'
      },
      npcProfile,
      []
    )

    return reply.send(result)
  })
}
