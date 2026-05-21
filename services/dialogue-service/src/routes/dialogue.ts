import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { NPCEngine } from '../services/npc-engine.js'
import { CoachPublisher } from '../services/coach-publisher.js'

const dialogueSchema = z.object({
  npc_id: z.string(),
  player_input: z.string().min(1).max(500),
  session_id: z.string(),
  language: z.string().default('en'),
})

export async function registerDialogueRoutes(app: FastifyInstance, coachPublisher: CoachPublisher) {
  const npcEngine = new NPCEngine()

  app.post('/api/v1/dialogue', async (request, reply) => {
    const body = dialogueSchema.parse(request.body)
    const userId = 'anonymous'

    const npcProfile = {
      name: 'Default NPC',
      npc_type: 'merchant',
      language_style: 'friendly',
      formality: 'informal' as const,
      vocabulary_level: 'basic' as const,
      personality: 'helpful',
      role: 'merchant',
      cefr_level: 'A1',
    }

    const result = await npcEngine.processDialogue(
      {
        ...body,
        user_id: userId,
        cefr_level: 'A1',
      },
      npcProfile,
      [],
    )

    void coachPublisher.publishDialogueTurn({
      session_id: body.session_id,
      user_id: userId,
      npc_id: body.npc_id,
      player_text: body.player_input,
      npc_response: result.npc_text,
      language: body.language,
      timestamp: Date.now(),
    }).catch((error) => app.log.error(error))

    return reply.send(result)
  })
}
